import 'package:latlong2/latlong.dart';

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

  String get address => tags['addr:street'] ?? tags['addr:full'] ?? '';
}