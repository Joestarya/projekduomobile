import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────
enum NodeType { atm, bank, other }

class AtmNode {
  final String id;
  final LatLng position;
  final String label;
  final NodeType type;
  final Map<String, String> tags;

  const AtmNode({
    required this.id,
    required this.position,
    required this.label,
    required this.type,
    required this.tags,
  });

  String get bankName =>
      tags['operator'] ?? tags['name'] ?? tags['brand'] ?? '';

  String get address =>
      tags['addr:street'] ?? tags['addr:full'] ?? '';
}

// ─────────────────────────────────────────────
//  THEME CONSTANTS  (Warm Earth / Terracotta)
// ─────────────────────────────────────────────
class AppTheme {
  static const bg          = Color(0xFF1E2738);
  static const surface     = Color(0xFF283548);
  static const surfaceHigh = Color(0xFF324158);
  static const border      = Color(0xFF3E4F6A);
  static const accent      = Color(0xFF638BFF);   // soft blue
  static const accentSoft  = Color(0xFF4FA0FF);
  static const atmColor    = Color(0xFF638BFF);   // soft blue
  static const bankColor   = Color(0xFF8B9BB4);   // slate
  static const userColor   = Color(0xFFFF6B6B);   // coral
  static const textPrimary = Colors.white;
  static const textMuted   = Color(0xFF8B9BB4);
  static const textDim     = Color(0xFF6A7B96);
}

// ─────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────
class AtmFinderScreen extends StatefulWidget {
  const AtmFinderScreen({super.key});
  @override
  State<AtmFinderScreen> createState() => _AtmFinderScreenState();
}

class _AtmFinderScreenState extends State<AtmFinderScreen>
    with TickerProviderStateMixin {

  // Map
  final MapController _mapCtrl = MapController();
  LatLng? _myLocation;

  // Data
  List<AtmNode> _nodes = [];
  AtmNode? _selectedNode;
  bool _isLoading = false;
  String? _errorMsg;

  // Settings
  double _radius = 1000;
  static const double _minR = 500;
  static const double _maxR = 10000;
  bool _showBanks = true;
  bool _showATMs = true;
  bool _radiusPanelExpanded = false;

  // Live tracking
  StreamSubscription<Position>? _locationSub;
  LatLng? _lastFetchedLoc;
  static const double _refetchThreshold = 150;

  // Animation
  late AnimationController _pulseCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  //route

  List<LatLng> _routePoints = [];
  bool _isRouting = false;
  String? _routeInfo;

  // Bottom sheet
  bool _showBottomSheet = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = CurvedAnimation(
      parent: _slideCtrl,
      curve: Curves.easeOutCubic,
    );

    _initMap();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── INIT ──────────────────────────────────
  Future<void> _initMap() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    final loc = await _getLocation();
    if (loc != null) {
      await _fetchNodes(loc);
      _startTracking();
    }
    if (mounted) setState(() => _isLoading = false);
  }

// ── FETCH ROUTE (OSRM API) ────────────────
  Future<void> _fetchRoute(LatLng destination) async {
    if (_myLocation == null) return;
    
    setState(() { 
      _isRouting = true; 
      _routePoints = []; 
      _routeInfo = null; 
    });

    final start = _myLocation!;
    // Format OSRM: longitude,latitude
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?geometries=geojson&overview=full');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['code'] == 'Ok') {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;
          
          // OSRM mengembalikan [longitude, latitude], latlong2 butuh (latitude, longitude)
          final points = geometry.map((coord) => LatLng(coord[1], coord[0])).toList();
          
          final distance = route['distance'] as num; // dalam meter
          final duration = route['duration'] as num; // dalam detik

          setState(() {
            _routePoints = points;
            _routeInfo = '${(distance / 1000).toStringAsFixed(1)} km • ${(duration / 60).toStringAsFixed(0)} mnt';
          });
        }
      }
    } catch (e) {
      _setError('Gagal memuat rute navigasi.');
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  // ── LOCATION ──────────────────────────────
  Future<LatLng?> _getLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setError('GPS tidak aktif. Nyalakan lokasi terlebih dahulu.');
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _setError('Izin lokasi ditolak. Buka Pengaturan untuk mengaktifkan.');
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      final loc = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _myLocation = loc);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapCtrl.move(loc, 15.5);
        });
      }
      return loc;
    } catch (e) {
      _setError('Gagal mendapatkan lokasi: $e');
      return null;
    }
  }

  void _startTracking() {
    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) async {
      final newLoc = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() => _myLocation = newLoc);

      if (_lastFetchedLoc != null && !_isLoading) {
        final dist = const Distance().as(
          LengthUnit.Meter, _lastFetchedLoc!, newLoc);
        if (dist >= _refetchThreshold) await _fetchNodes(newLoc);
      }
    });
  }

  // ── FETCH ATM DATA ─────────────────────────
  Future<void> _fetchNodes(LatLng loc) async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMsg = null; });

    final r   = _radius.toInt();
    final lat = loc.latitude;
    final lon = loc.longitude;

    // Query komprehensif: ATM + Bank + nama/operator bank Indonesia
    final query = '''
[out:json][timeout:30];
(
  node["amenity"="atm"](around:$r,$lat,$lon);
  way["amenity"="atm"](around:$r,$lat,$lon);
  node["amenity"="bank"](around:$r,$lat,$lon);
  way["amenity"="bank"](around:$r,$lat,$lon);
  node["name"~"ATM",i](around:$r,$lat,$lon);
  node["operator"~"BCA|BRI|Mandiri|BNI|CIMB|Danamon|BTN|Permata|Maybank|OCBC|BSI|Panin|Mega",i](around:$r,$lat,$lon);
);
out center tags;
''';

    final url = Uri.parse(
      'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}',
    );

    try {
      final res = await http.get(url,
        headers: {'User-Agent': 'ATMFinderApp/2.0'})
        .timeout(const Duration(seconds: 35));

      if (!mounted) return;
      if (res.statusCode != 200) {
        _setError('Server error (${res.statusCode}). Coba lagi.');
        return;
      }

      final data     = json.decode(res.body) as Map<String, dynamic>;
      final elements = data['elements'] as List;
      final seen     = <String>{};
      final nodes    = <AtmNode>[];

      for (final el in elements) {
        final double? elLat = el['type'] == 'way'
            ? (el['center']?['lat'] as num?)?.toDouble()
            : (el['lat'] as num?)?.toDouble();
        final double? elLon = el['type'] == 'way'
            ? (el['center']?['lon'] as num?)?.toDouble()
            : (el['lon'] as num?)?.toDouble();
        if (elLat == null || elLon == null) continue;

        final key = '${elLat.toStringAsFixed(5)}_${elLon.toStringAsFixed(5)}';
        if (seen.contains(key)) continue;
        seen.add(key);

        final tags    = (el['tags'] as Map?)?.cast<String, String>() ?? {};
        final amenity = tags['amenity'] ?? '';
        final id      = '${el['type']}_${el['id']}';

        NodeType type;
        String label;

        if (amenity == 'atm') {
          type  = NodeType.atm;
          label = tags['operator'] ?? tags['name'] ?? tags['brand'] ?? 'ATM';
        } else if (amenity == 'bank') {
          type  = NodeType.bank;
          label = tags['name'] ?? tags['operator'] ?? 'Bank';
        } else {
          type  = NodeType.other;
          label = tags['name'] ?? tags['operator'] ?? 'ATM';
        }

        nodes.add(AtmNode(
          id: id,
          position: LatLng(elLat, elLon),
          label: label,
          type: type,
          tags: tags,
        ));
      }

      setState(() {
        _nodes = nodes;
        _lastFetchedLoc = loc;
        if (nodes.isEmpty) {
          _errorMsg = 'Tidak ada ATM/Bank ditemukan dalam radius ${_radius.toInt()}m.\nCoba perbesar radius scan.';
        }
      });
    } catch (e) {
      if (mounted) _setError('Koneksi bermasalah. Periksa internet kamu.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String msg) {
    if (mounted) setState(() { _errorMsg = msg; _isLoading = false; });
  }

  // ── FILTER ────────────────────────────────
  List<AtmNode> get _filteredNodes => _nodes.where((n) {
    if (n.type == NodeType.atm   && !_showATMs)  return false;
    if (n.type == NodeType.bank  && !_showBanks) return false;
    return true;
  }).toList();

  // ── SELECT NODE ───────────────────────────
  void _selectNode(AtmNode node) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedNode    = node;
      _showBottomSheet = true;
      _routePoints = []; //reset route
      _routeInfo = null;
    });
    _slideCtrl.forward(from: 0);
    _mapCtrl.move(node.position, 16.0);
  }

  void _closeBottomSheet() {
    _slideCtrl.reverse().then((_) {
      if (mounted) setState(() { _showBottomSheet = false; _selectedNode = null; });
      _routePoints = []; // Reset rute 
      _routeInfo = null;
    });
  }

  // ── BUILD ──────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: Stack(
          children: [
            _buildMap(),
            _buildTopHUD(),
            _buildRadiusPanel(),
            if (_showBottomSheet && _selectedNode != null)
              _buildNodeSheet(_selectedNode!),
            _buildBottomControls(),
            if (_isLoading) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

Widget _infoRow(IconData icon, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.textMuted, size: 13),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 10,
                      letterSpacing: 0.5)),
              Text(value,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}
  // ── MAP ───────────────────────────────────
  Widget _buildMap() {
    final filtered = _filteredNodes;
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: const LatLng(-6.2088, 106.8456),
        initialZoom: 15.0,
        onTap: (_, __) => _closeBottomSheet(),
      ),
      children: [
        // OSM Standard tiles — gratis, no API key
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.atmfinder.app',
          maxZoom: 19,
        ),

        // Radius circle overlay
        if (_myLocation != null)
          CircleLayer(circles: [
            CircleMarker(
              point: _myLocation!,
              radius: _radius,
              useRadiusInMeter: true,
              color: AppTheme.accent.withOpacity(0.06),
              borderColor: AppTheme.accent.withOpacity(0.25),
              borderStrokeWidth: 1.5,
            ),
          ]),

        // ATM / Bank markers
        // Route Polyline (Tambahkan bagian ini)
        PolylineLayer(
          polylines: [
            if (_routePoints.isNotEmpty)
              Polyline(
                points: _routePoints,
                color: AppTheme.accentSoft, // Warna garis rute
                strokeWidth: 4.5,           // Ketebalan garis
                borderColor: AppTheme.accent,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            ...filtered.map((node) => Marker(
              point: node.position,
              width: 120,
              height: 72,
              child: GestureDetector(
                onTap: () => _selectNode(node),
                child: _buildMarker(node),
              ),
            )),

            // User location
            if (_myLocation != null)
              Marker(
                point: _myLocation!,
                width: 64,
                height: 64,
                child: _buildUserMarker(),
              ),
          ],
        ),
      ],
    );
  }

  // ── MARKER WIDGETS ────────────────────────
  Widget _buildMarker(AtmNode node) {
    final isSelected = _selectedNode?.id == node.id;
    final color = node.type == NodeType.bank ? AppTheme.bankColor : AppTheme.atmColor;

    return AnimatedScale(
      scale: isSelected ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 110),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? color : AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(isSelected ? 0.5 : 0.2),
                  blurRadius: isSelected ? 12 : 6,
                  spreadRadius: isSelected ? 2 : 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  node.type == NodeType.bank
                      ? Icons.account_balance_rounded
                      : Icons.credit_card_rounded,
                  color: isSelected ? AppTheme.bg : color,
                  size: 11,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    node.label,
                    style: TextStyle(
                      color: isSelected ? AppTheme.bg : AppTheme.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          // Stem
          Container(
            width: 2,
            height: 6,
            color: color.withOpacity(0.6),
          ),
          // Dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.6), blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMarker() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final pulse = _pulseCtrl.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 48 + pulse * 12,
              height: 48 + pulse * 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.userColor.withOpacity(0.1 * (1 - pulse)),
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.userColor.withOpacity(0.2),
                border: Border.all(color: AppTheme.userColor, width: 2),
              ),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.userColor,
                boxShadow: [
                  BoxShadow(color: AppTheme.userColor.withOpacity(0.7), blurRadius: 10, spreadRadius: 3),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

// ── TOP HUD (lebih compact) ──────────────────
Widget _buildTopHUD() {
  final filtered = _filteredNodes;
  final atmCount  = filtered.where((n) => n.type != NodeType.bank).length;
  final bankCount = filtered.where((n) => n.type == NodeType.bank).length;

  return Positioned(
    top: MediaQuery.of(context).padding.top + 8,
    left: 16,
    right: 16,
    child: _glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _locationSub != null
                      ? const Color(0xFF52D48F)
                      : AppTheme.textDim,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'ATM Finder',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!_isLoading && _errorMsg == null) ...[
            _statChip(atmCount.toString(), 'ATM', AppTheme.atmColor),
            const SizedBox(width: 6),
            _statChip(bankCount.toString(), 'Bank', AppTheme.bankColor),
          ] else if (_isLoading)
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
            )
          else
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent.shade200, size: 18),
        ],
      ),
    ),
  );
}

Widget _statChip(String count, String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(count, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
      ],
    ),
  );
}

// ── RADIUS PANEL (collapsible) ────────────────
Widget _buildRadiusPanel() {
  return Positioned(
    top: MediaQuery.of(context).padding.top + 62,
    left: 16,
    right: 16,
    child: _glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tap row untuk expand/collapse ──
          GestureDetector(
            onTap: () => setState(() => _radiusPanelExpanded = !_radiusPanelExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.radar_rounded, color: AppTheme.accent, size: 14),
                const SizedBox(width: 6),
                Text(
                  _radius >= 1000
                      ? '${(_radius / 1000).toStringAsFixed(1)} km'
                      : '${_radius.toInt()} m',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip('ATM', AppTheme.atmColor, _showATMs,
                    (v) => setState(() => _showATMs = v)),
                const SizedBox(width: 6),
                _filterChip('Bank', AppTheme.bankColor, _showBanks,
                    (v) => setState(() => _showBanks = v)),
                const Spacer(),
                Icon(
                  _radiusPanelExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),

          // ── Slider (hanya muncul kalau expanded) ──
          if (_radiusPanelExpanded) ...[
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.accent,
                inactiveTrackColor: AppTheme.border,
                thumbColor: AppTheme.accent,
                overlayColor: AppTheme.accent.withOpacity(0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                trackHeight: 3,
              ),
              child: Slider(
                value: _radius,
                min: _minR,
                max: _maxR,
                divisions: 18,
                onChanged: (v) => setState(() => _radius = v),
                onChangeEnd: (v) {
                  if (_myLocation != null && !_isLoading) _fetchNodes(_myLocation!);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('500 m', style: TextStyle(color: AppTheme.textDim, fontSize: 9)),
                Text('10 km',  style: TextStyle(color: AppTheme.textDim, fontSize: 9)),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _filterChip(String label, Color color, bool active, ValueChanged<bool> onTap) {
  return GestureDetector(
    onTap: () => onTap(!active),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.18) : AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? color.withOpacity(0.5) : AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: active ? color : AppTheme.textDim,
            size: 10,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: active ? color : AppTheme.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── NODE DETAIL SHEET (compact + scroll) ──────
Widget _buildNodeSheet(AtmNode node) {
  final color = node.type == NodeType.bank ? AppTheme.bankColor : AppTheme.atmColor;
  return Positioned(
    left: 0, right: 0, bottom: 0,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_slideAnim),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 90),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.35,
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 8)),
            BoxShadow(color: color.withOpacity(0.1), blurRadius: 24),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── HEADER ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Icon(
                      node.type == NodeType.bank
                          ? Icons.account_balance_rounded
                          : Icons.credit_card_rounded,
                      color: color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.label,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          node.type == NodeType.bank
                              ? 'Kantor Bank'
                              : 'ATM / Mesin Tunai',
                          style: TextStyle(
                              color: color.withOpacity(0.8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _closeBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceHigh,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: AppTheme.textMuted, size: 16),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Container(height: 1, color: AppTheme.border),
              const SizedBox(height: 10),

              // ── INFO ROWS ──
              if (node.bankName.isNotEmpty)
                _infoRow(Icons.business_rounded, 'Operator', node.bankName),
              if (node.address.isNotEmpty)
                _infoRow(Icons.location_on_rounded, 'Alamat', node.address),
              if (_myLocation != null)
                _infoRow(
                  Icons.directions_walk_rounded,
                  'Jarak',
                  '${const Distance().as(LengthUnit.Meter, _myLocation!, node.position).toStringAsFixed(0)} m',
                ),

              const SizedBox(height: 10),

              // ── ROUTE BUTTON ──
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _isRouting ? null : () => _fetchRoute(node.position),
                      icon: _isRouting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.directions, size: 16),
                      label: Text(
                        _isRouting ? 'Mencari rute...' : 'Tampilkan Rute',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: AppTheme.bg,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (_routeInfo != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _routeInfo!,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── BOTTOM CONTROLS (lebih compact) ──────────
Widget _buildBottomControls() {
  return Positioned(
    bottom: 20,
    left: 16,
    right: 16,
    child: Row(
      children: [
        Expanded(
          child: _glass(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.my_location_rounded,
                  color: AppTheme.userColor.withOpacity(0.8),
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _myLocation != null
                        ? '${_myLocation!.latitude.toStringAsFixed(5)}, ${_myLocation!.longitude.toStringAsFixed(5)}'
                        : 'Mendeteksi lokasi...',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _iconBtn(
          icon: Icons.navigation_rounded,
          color: AppTheme.userColor,
          onTap: _myLocation != null
              ? () {
                  HapticFeedback.lightImpact();
                  _mapCtrl.move(_myLocation!, 15.5);
                }
              : null,
        ),
        const SizedBox(width: 6),
        _iconBtn(
          icon: _isLoading
              ? Icons.hourglass_top_rounded
              : Icons.refresh_rounded,
          color: AppTheme.accent,
          onTap: _isLoading
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  _initMap();
                },
        ),
      ],
    ),
  );
}

Widget _iconBtn({
  required IconData icon,
  required Color color,
  VoidCallback? onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: onTap != null ? color.withOpacity(0.4) : AppTheme.border),
        boxShadow: [
          if (onTap != null)
            BoxShadow(
                color: color.withOpacity(0.2), blurRadius: 8, spreadRadius: 0),
        ],
      ),
      child: Icon(icon,
          color: onTap != null ? color : AppTheme.textDim, size: 20),
    ),
  );
}
  // ── LOADING OVERLAY ───────────────────────
  Widget _buildLoadingOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 300,
      left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(color: AppTheme.accent.withOpacity(0.15), blurRadius: 16),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  color: AppTheme.accent, strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Mencari ATM terdekat...',
                style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ERROR SNACKBAR ─────────────────────────
  // Error ditampilkan via error state di HUD, bukan snackbar

  // ── GLASS CONTAINER ───────────────────────
  Widget _glass({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: child,
        ),
      ),
    );
  }
}