import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../theme/app_theme.dart';
import 'map_models.dart';
import 'map_service.dart';

class AtmFinderScreen extends StatefulWidget {
  const AtmFinderScreen({super.key});
  @override
  State<AtmFinderScreen> createState() => _AtmFinderScreenState();
}

class _AtmFinderScreenState extends State<AtmFinderScreen>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  LatLng? _myLocation;
  List<AtmNode> _nodes = [];
  AtmNode? _selectedNode;
  bool _isLoading = false;
  String? _errorMsg;
  double _radius = 1000;
  static const double _minR = 500;
  static const double _maxR = 10000;
  bool _showBanks = true;
  bool _showATMs = true;
  bool _radiusPanelExpanded = false;

  StreamSubscription<Position>? _locationSub;
  LatLng? _lastFetchedLoc;

  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  List<LatLng> _routePoints = [];
  bool _isRouting = false;
  String? _routeInfo;
  bool _showBottomSheet = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
    _initMap();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _initMap() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final loc = await _getLocation();
    if (loc != null) {
      await _fetchNodes(loc);
      _startTracking();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<LatLng?> _getLocation() async {
    try {
      final loc = await MapService.getLocation();
      if (loc == null) {
        _setError('Gagal mendapatkan lokasi atau izin ditolak.');
        return null;
      }
      if (mounted) {
        setState(() => _myLocation = loc);
        WidgetsBinding.instance.addPostFrameCallback((_) => _mapCtrl.move(loc, 15.5));
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((pos) async {
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
      final newLoc = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() => _myLocation = newLoc);

      if (_lastFetchedLoc != null && !_isLoading) {
        final dist = const Distance().as(LengthUnit.Meter, _lastFetchedLoc!, newLoc);
        if (dist >= MapService.refetchThreshold) await _fetchNodes(newLoc);
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _fetchNodes(LatLng loc) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final nodes = await MapService.fetchNodes(loc, _radius);
      if (!mounted) return;

      setState(() {
        _nodes = nodes;
        _lastFetchedLoc = loc;
        if (_selectedNode != null && !nodes.any((n) => n.id == _selectedNode!.id)) {
          _selectedNode = null;
          _showBottomSheet = false;
          _routePoints = [];
          _routeInfo = null;
        }
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

  Future<void> _fetchRoute(LatLng destination) async {
    if (_myLocation == null) return;
    setState(() {
      _isRouting = true;
      _routePoints = [];
      _routeInfo = null;
    });

    try {
      final result = await MapService.fetchRoute(_myLocation!, destination);
      if (result != null && mounted) {
        setState(() {
          _routePoints = result.points;
          _routeInfo = result.info;
        });
      }
    } catch (e) {
      _setError('Gagal memuat rute navigasi.');
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  void _setError(String msg) {
    if (mounted) setState(() {
      _errorMsg = msg;
      _isLoading = false;
    });
  }

  List<AtmNode> get _filteredNodes => _nodes.where((n) {
    if (n.type == NodeType.atm && !_showATMs) return false;
    if (n.type == NodeType.bank && !_showBanks) return false;
    return true;
  }).toList();

  void _selectNode(AtmNode node) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedNode = node;
      _showBottomSheet = true;
      _routePoints = [];
      _routeInfo = null;
    });
    _slideCtrl.forward(from: 0);
    _mapCtrl.move(node.position, 16.0);
  }

  void _closeBottomSheet() {
    _slideCtrl.reverse().then((_) {
      if (mounted) setState(() {
        _showBottomSheet = false;
        _selectedNode = null;
      });
      _routePoints = [];
      _routeInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: Stack(
          children: [
            _buildMap(),
            _buildTopHUD(),
            _buildRadiusPanel(),
            if (_showBottomSheet && _selectedNode != null) _buildNodeSheet(_selectedNode!),
            _buildBottomControls(),
            if (_isLoading) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

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
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.atmfinder.app',
          maxZoom: 19,
        ),
        if (_myLocation != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: _myLocation!,
                radius: _radius,
                useRadiusInMeter: true,
                color: AppTheme.accent.withOpacity(0.06),
                borderColor: AppTheme.accent.withOpacity(0.25),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        PolylineLayer(
          polylines: [
            if (_routePoints.isNotEmpty)
              Polyline(
                points: _routePoints,
                color: AppTheme.accentSoft,
                strokeWidth: 4,
                borderColor: AppTheme.accent,
                borderStrokeWidth: 1,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            ...filtered.map((node) => Marker(
              point: node.position,
              width: 120,
              height: 72,
              child: GestureDetector(onTap: () => _selectNode(node), child: _buildMarker(node)),
            )),
            if (_myLocation != null)
              Marker(
                point: _myLocation!,
                width: 48,
                height: 48,
                child: _buildUserMarker(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMarker(AtmNode node) {
    final isSelected = _selectedNode?.id == node.id;
    final color = node.type == NodeType.bank ? AppTheme.bankColor : AppTheme.atmColor;

    return AnimatedScale(
      scale: isSelected ? 1.15 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 110),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? color : AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color, width: isSelected ? 2 : 1),
              boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 6)] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  node.type == NodeType.bank ? Icons.account_balance_rounded : Icons.credit_card_rounded,
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
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 2, height: 6, color: color.withOpacity(0.6)),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.userColor,
            boxShadow: [BoxShadow(color: AppTheme.userColor.withOpacity(0.4), blurRadius: 4)],
          ),
        ),
      ],
    );
  }

  Widget _buildTopHUD() {
    final filtered = _filteredNodes;
    final atmCount = filtered.where((n) => n.type != NodeType.bank).length;
    final bankCount = filtered.where((n) => n.type == NodeType.bank).length;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _locationSub != null ? const Color(0xFF52D48F) : AppTheme.textDim)),
                const SizedBox(width: 5),
                const Text('ATM Finder', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
            const Spacer(),
            if (!_isLoading && _errorMsg == null) ...[
              _statChip(atmCount.toString(), 'ATM', AppTheme.atmColor),
              const SizedBox(width: 6),
              _statChip(bankCount.toString(), 'Bank', AppTheme.bankColor),
            ] else if (_isLoading)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2))
            else
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent.shade200, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(count, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildRadiusPanel() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _radiusPanelExpanded = !_radiusPanelExpanded),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(Icons.radar_rounded, color: AppTheme.accent, size: 13),
                  const SizedBox(width: 5),
                  Text(_radius >= 1000 ? '${(_radius / 1000).toStringAsFixed(1)} km' : '${_radius.toInt()} m',
                    style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  _filterChip('ATM', AppTheme.atmColor, _showATMs, (v) => setState(() => _showATMs = v)),
                  const SizedBox(width: 5),
                  _filterChip('Bank', AppTheme.bankColor, _showBanks, (v) => setState(() => _showBanks = v)),
                  const Spacer(),
                  Icon(_radiusPanelExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppTheme.textMuted, size: 16),
                ],
              ),
            ),
            if (_radiusPanelExpanded) ...[
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.accent,
                  inactiveTrackColor: AppTheme.border,
                  thumbColor: AppTheme.accent,
                  overlayColor: AppTheme.accent.withOpacity(0.15),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                Text('500 m', style: TextStyle(color: AppTheme.textDim, fontSize: 8)),
                Text('10 km', style: TextStyle(color: AppTheme.textDim, fontSize: 8)),
              ]),
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
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: active ? color.withOpacity(0.4) : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined, color: active ? color : AppTheme.textDim, size: 9),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(color: active ? color : AppTheme.textDim, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeSheet(AtmNode node) {
    final color = node.type == NodeType.bank ? AppTheme.bankColor : AppTheme.atmColor;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(_slideAnim),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 90),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Icon(node.type == NodeType.bank ? Icons.account_balance_rounded : Icons.credit_card_rounded, color: color, size: 16),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(node.label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(node.type == NodeType.bank ? 'Bank' : 'ATM', style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _closeBottomSheet,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Container(height: 0.8, color: AppTheme.border),
                const SizedBox(height: 9),
                if (node.bankName.isNotEmpty)
                  _infoRow(Icons.business_rounded, 'Operator', node.bankName),
                if (node.address.isNotEmpty)
                  _infoRow(Icons.location_on_rounded, 'Alamat', node.address),
                if (_myLocation != null)
                  _infoRow(Icons.directions_walk_rounded, 'Jarak',
                    '${const Distance().as(LengthUnit.Meter, _myLocation!, node.position).toStringAsFixed(0)} m'),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRouting ? null : () => _fetchRoute(node.position),
                        icon: _isRouting
                            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.directions, size: 15),
                        label: Text(_isRouting ? 'Mencari rute...' : 'Tampilkan Rute', style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: AppTheme.bg,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    if (_routeInfo != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(8)),
                        child: Text(_routeInfo!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 10)),
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

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textDim, fontSize: 9)),
                Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(color: AppTheme.surface.withOpacity(0.95), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
              child: Row(
                children: [
                  Icon(Icons.my_location_rounded, color: AppTheme.userColor.withOpacity(0.7), size: 12),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _myLocation != null ? '${_myLocation!.latitude.toStringAsFixed(5)}, ${_myLocation!.longitude.toStringAsFixed(5)}' : 'Mendeteksi lokasi...',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.navigation_rounded, AppTheme.userColor, _myLocation != null ? () {
            HapticFeedback.lightImpact();
            _mapCtrl.move(_myLocation!, 15.5);
          } : null),
          const SizedBox(width: 6),
          _iconBtn(_isLoading ? Icons.hourglass_top_rounded : Icons.refresh_rounded, AppTheme.accent, _isLoading ? null : () {
            HapticFeedback.mediumImpact();
            _initMap();
          }),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: onTap != null ? color.withOpacity(0.3) : AppTheme.border),
          boxShadow: onTap != null ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 4)] : null,
        ),
        child: Icon(icon, color: onTap != null ? color : AppTheme.textDim, size: 18),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 300,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.1), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)),
              const SizedBox(width: 8),
              const Text('Mencari ATM terdekat...', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
