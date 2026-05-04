import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'map_models.dart';

// ─────────────────────────────────────────────
//  SERVICE — Network, Location, Route
// ─────────────────────────────────────────────
class MapService {
  static const double refetchThreshold = 150;

  // ── GET USER LOCATION ─────────────────────
  static Future<LatLng?> getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final pos = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // ── FETCH ATM/BANK NODES (Overpass API) ───
  static Future<List<AtmNode>> fetchNodes(LatLng center, double radiusM) async {
    final r = radiusM.toInt();
    final lat = center.latitude;
    final lon = center.longitude;

    // Query komprehensif: ATM + Bank menggunakan `around` (lingkaran akurat)
    final query = '''
[out:json][timeout:30];
(
  node["amenity"="atm"](around:$r,$lat,$lon);
  node["amenity"="bank"](around:$r,$lat,$lon);
  way["amenity"="bank"](around:$r,$lat,$lon);
);
out center tags;
''';

    final url = Uri.parse(
      'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}',
    );

    final nodes = <AtmNode>[];
    final seen = <String>{};

    try {
      final res = await http
          .get(url, headers: {'User-Agent': 'ATMFinderApp/2.0'})
          .timeout(const Duration(seconds: 35));

      if (res.statusCode != 200) return nodes;

      final data = json.decode(res.body) as Map<String, dynamic>;
      final elements = data['elements'] as List;

      for (final el in elements) {
        // Ambil koordinat — node punya lat/lon langsung, way punya center
        final double? elLat = el['type'] == 'way'
            ? (el['center']?['lat'] as num?)?.toDouble()
            : (el['lat'] as num?)?.toDouble();
        final double? elLon = el['type'] == 'way'
            ? (el['center']?['lon'] as num?)?.toDouble()
            : (el['lon'] as num?)?.toDouble();

        if (elLat == null || elLon == null) continue;

        // Deduplikasi berdasarkan posisi (hindari ATM + bank overlap)
        final key = '${elLat.toStringAsFixed(6)},${elLon.toStringAsFixed(6)}';
        if (seen.contains(key)) continue;
        seen.add(key);

        final tags = (el['tags'] as Map?)?.cast<String, String>() ?? {};
        final amenity = tags['amenity'] ?? '';
        final id = '${el['type']}_${el['id']}';

        NodeType type;
        String label;

        if (amenity == 'atm') {
          type = NodeType.atm;
          label = tags['operator'] ?? tags['name'] ?? tags['brand'] ?? 'ATM';
        } else if (amenity == 'bank') {
          type = NodeType.bank;
          label = tags['name'] ?? tags['operator'] ?? 'Bank';
        } else {
          type = NodeType.other;
          label = tags['name'] ?? tags['operator'] ?? 'ATM';
        }

        nodes.add(
          AtmNode(
            id: id,
            position: LatLng(elLat, elLon),
            label: label,
            type: type,
            tags: tags,
          ),
        );
      }
    } catch (_) {}

    return nodes;
  }

  // ── FETCH ROUTE (OSRM API) ────────────────
  static Future<({List<LatLng> points, String info})?> fetchRoute(
    LatLng start,
    LatLng end,
  ) async {
    // Format OSRM: longitude,latitude
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?geometries=geojson&overview=full',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;

      final route = data['routes'][0] as Map<String, dynamic>;
      final geometry = route['geometry']['coordinates'] as List;

      // OSRM mengembalikan [longitude, latitude], latlong2 butuh (latitude, longitude)
      final points = geometry
          .map((coord) => LatLng(coord[1] as double, coord[0] as double))
          .toList();

      final distance = route['distance'] as num; // dalam meter
      final duration = route['duration'] as num; // dalam detik
      final info =
          '${(distance / 1000).toStringAsFixed(1)} km • ${(duration / 60).toStringAsFixed(0)} mnt';

      return (points: points, info: info);
    } catch (_) {
      return null;
    }
  }

  // ── CHECK SHOULD REFETCH ──────────────────
  static bool shouldRefetch(LatLng? last, LatLng current) {
    if (last == null) return true;
    final dist = const Distance().as(LengthUnit.Meter, last, current);
    return dist > refetchThreshold;
  }
}