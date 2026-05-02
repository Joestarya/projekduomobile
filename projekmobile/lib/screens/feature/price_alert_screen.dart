// ============================================================
// lib/screens/feature/price_alert_screen.dart
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/api_config.dart';

// ── Model ─────────────────────────────────────────────────────
class _Alert {
  final int    id;
  final String coinSymbol;
  final double targetPrice;
  final String direction;
  final String status;

  const _Alert({
    required this.id,
    required this.coinSymbol,
    required this.targetPrice,
    required this.direction,
    required this.status,
  });

  factory _Alert.fromJson(Map<String, dynamic> j) => _Alert(
        id:          j['id'] as int,
        coinSymbol:  j['coin_symbol'] as String,
        targetPrice: double.parse(j['target_price'].toString()),
        direction:   j['direction'] as String,
        status:      j['status'] as String,
      );
}

// ── Konfigurasi tiap coin ──────────────────────────────────────
class _CoinConfig {
  final String symbol;
  final List<Color> gradient;
  final String emoji;

  const _CoinConfig({
    required this.symbol,
    required this.gradient,
    required this.emoji,
  });
}

const _coins = [
  _CoinConfig(symbol: 'BTC', gradient: [Color(0xFFFF9800), Color(0xFFFFB74D)], emoji: '₿'),
  _CoinConfig(symbol: 'ETH', gradient: [Color(0xFF627EEA), Color(0xFF8BA4F7)], emoji: 'Ξ'),
  _CoinConfig(symbol: 'BNB', gradient: [Color(0xFFF3BA2F), Color(0xFFFFE082)], emoji: 'B'),
  _CoinConfig(symbol: 'SOL', gradient: [Color(0xFF9945FF), Color(0xFF19FB9B)], emoji: '◎'),
];

// Persentase quick alert yang tersedia
const _percentages = [1, 2, 3, 5, 10, 15, 20];

// ── Screen ─────────────────────────────────────────────────────
class PriceAlertScreen extends StatefulWidget {
  // Harga live dikirim dari DashboardScreen
  final Map<String, double> livePrices; // e.g. {'BTC': 68000.0, ...}

  const PriceAlertScreen({super.key, required this.livePrices});

  @override
  State<PriceAlertScreen> createState() => _PriceAlertScreenState();
}

class _PriceAlertScreenState extends State<PriceAlertScreen>
    with SingleTickerProviderStateMixin {
  List<_Alert> _alerts = [];
  bool _isLoading = true;
  String? _userId;

  // Form state
  int _selectedCoinIdx = 0;
  String _direction = 'up';
  int? _selectedPct;
  bool _isSubmitting = false;
  bool _isManualMode = false; // false = Quick %, true = Manual Price
  final _manualPriceController = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadUser();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _manualPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    if (_userId != null) await _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    setState(() => _isLoading = true);
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.endpoint('/alerts?user_id=$_userId')))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _alerts = (data['alerts'] as List)
              .map((e) => _Alert.fromJson(e as Map<String, dynamic>))
              .toList();
        });
        _fadeCtrl.forward(from: 0);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Hitung harga target dari persentase atau manual ────────
  double? get _targetPrice {
    if (_isManualMode) {
      final text = _manualPriceController.text.trim().replaceAll(',', '.');
      final val = double.tryParse(text);
      return (val != null && val > 0) ? val : null;
    }
    if (_selectedPct == null) return null;
    final symbol = _coins[_selectedCoinIdx].symbol;
    final livePrice = widget.livePrices[symbol];
    if (livePrice == null || livePrice == 0) return null;
    final mult = _direction == 'up'
        ? 1 + (_selectedPct! / 100)
        : 1 - (_selectedPct! / 100);
    return livePrice * mult;
  }

  // Cek apakah tombol Set Alert bisa ditekan
  bool get _canSubmit {
    if (_isManualMode) return _targetPrice != null;
    return _selectedPct != null;
  }

  Future<void> _createAlert() async {
    final target = _targetPrice;
    if (target == null) {
      _snack(
        _isManualMode ? 'Masukkan harga target yang valid' : 'Pilih persentase terlebih dahulu',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.endpoint('/alerts')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id':      int.parse(_userId!),
          'coin_symbol':  _coins[_selectedCoinIdx].symbol,
          'target_price': target,
          'direction':    _direction,
        }),
      );

      if (resp.statusCode == 201) {
        setState(() {
          _selectedPct = null;
          _manualPriceController.clear();
        });
        _snack('Alert berhasil dibuat! 🔔');
        await _fetchAlerts();
      } else {
        final err = jsonDecode(resp.body);
        _snack(err['message'] ?? 'Gagal membuat alert', isError: true);
      }
    } catch (_) {
      _snack('Koneksi gagal', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteAlert(int id) async {
    try {
      final resp = await http.delete(
        Uri.parse(ApiConfig.endpoint('/alerts/$id?user_id=$_userId')),
      );
      if (resp.statusCode == 200) {
        setState(() => _alerts.removeWhere((a) => a.id == id));
        _snack('Alert dihapus');
      }
    } catch (_) {
      _snack('Gagal menghapus', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFFF5252) : const Color(0xFF00E676),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1427),
        elevation: 0,
        title: const Text(
          'Price Alert',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6C63FF)),
            onPressed: _fetchAlerts,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCreateCard(),
            const SizedBox(height: 24),
            _buildAlertList(),
          ],
        ),
      ),
    );
  }

  // ── Card buat alert baru ───────────────────────────────────
  Widget _buildCreateCard() {
    final coin = _coins[_selectedCoinIdx];
    final livePrice = widget.livePrices[coin.symbol];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1427),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E2D48)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: coin.gradient),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(coin.emoji,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(width: 10),
              const Text(
                'Buat Alert Baru',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              if (livePrice != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Live: \$${_fmtPrice(livePrice)}',
                    style: const TextStyle(
                        color: Color(0xFF9D97FF), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Pilih Coin ──
          const Text('Pilih Coin',
              style: TextStyle(color: Color(0xFF6C8EBF), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(_coins.length, (i) {
              final c = _coins[i];
              final isSelected = _selectedCoinIdx == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedCoinIdx = i;
                    _selectedPct = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: i < _coins.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(colors: c.gradient.map((cl) => cl.withOpacity(0.3)).toList())
                          : null,
                      color: isSelected ? null : const Color(0xFF131929),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? c.gradient.first : const Color(0xFF1E2D48),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(c.emoji,
                            style: const TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(c.symbol,
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF4A6080),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // ── Arah Alert ──
          const Text('Arah Alert',
              style: TextStyle(color: Color(0xFF6C8EBF), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _directionButton('up',   '📈  Naik (≥)',  const Color(0xFF00E676))),
              const SizedBox(width: 10),
              Expanded(child: _directionButton('down', '📉  Turun (≤)', const Color(0xFFFF5252))),
            ],
          ),
          const SizedBox(height: 20),

          // ── Mode Toggle: Quick % / Manual Price ──
          const Text('Metode Input Target',
              style: TextStyle(color: Color(0xFF6C8EBF), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF131929),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2D48)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _modeTab('⚡  Quick %', !_isManualMode, () => setState(() {
                  _isManualMode = false;
                  _manualPriceController.clear();
                })),
                _modeTab('✏️  Manual Price', _isManualMode, () => setState(() {
                  _isManualMode = true;
                  _selectedPct = null;
                })),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Konten berdasarkan mode ──
          if (!_isManualMode) ...[
            // QUICK % MODE
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _percentages.map((pct) {
                final isSelected = _selectedPct == pct;
                final color = _direction == 'up' ? const Color(0xFF00E676) : const Color(0xFFFF5252);
                final sign  = _direction == 'up' ? '+' : '-';
                String pricePreview = '';
                if (livePrice != null) {
                  final mult = _direction == 'up' ? 1 + (pct / 100) : 1 - (pct / 100);
                  pricePreview = '\$${_fmtPrice(livePrice * mult)}';
                }
                return GestureDetector(
                  onTap: () => setState(() => _selectedPct = isSelected ? null : pct),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.18) : const Color(0xFF131929),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : const Color(0xFF1E2D48),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$sign$pct%',
                          style: TextStyle(
                            color: isSelected ? color : const Color(0xFF6C8EBF),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        if (pricePreview.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            pricePreview,
                            style: TextStyle(
                              color: isSelected ? color.withOpacity(0.8) : const Color(0xFF3A5070),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            // MANUAL PRICE MODE
            TextField(
              controller: _manualPriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              onChanged: (_) => setState(() {}), // rebuild preview
              decoration: InputDecoration(
                hintText: livePrice != null ? 'Contoh: ${_fmtPrice(livePrice)}' : '0.00',
                hintStyle: const TextStyle(color: Color(0xFF3A5070)),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(
                    color: Color(0xFF6C8EBF), fontWeight: FontWeight.w600),
                filled: true,
                fillColor: const Color(0xFF131929),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _direction == 'up'
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF5252),
                    width: 1.5,
                  ),
                ),
                suffixText: 'USDT',
                suffixStyle: const TextStyle(color: Color(0xFF4A6080), fontSize: 12),
              ),
            ),
            // Tampilkan persentase jarak dari live price
            if (livePrice != null && _targetPrice != null) ...[
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final diff = ((_targetPrice! - livePrice) / livePrice * 100);
                final isPos = diff >= 0;
                final diffColor = isPos ? const Color(0xFF00E676) : const Color(0xFFFF5252);
                return Row(
                  children: [
                    Icon(
                      isPos ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: diffColor, size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isPos ? '+' : ''}${diff.toStringAsFixed(2)}% dari harga sekarang',
                      style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                );
              }),
            ],
          ],

          // ── Preview notif ──
          if (_targetPrice != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_rounded,
                      color: Color(0xFF9D97FF), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Color(0xFF9D97FF), fontSize: 13),
                        children: [
                          const TextSpan(text: 'Notif dikirim saat '),
                          TextSpan(
                            text: _coins[_selectedCoinIdx].symbol,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          TextSpan(text: ' ${_direction == 'up' ? 'naik ke ≥' : 'turun ke ≤'} '),
                          TextSpan(
                            text: '\$${_fmtPrice(_targetPrice!)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Tombol Set Alert ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isSubmitting || !_canSubmit) ? null : _createAlert,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canSubmit
                    ? (_direction == 'up' ? const Color(0xFF00E676) : const Color(0xFFFF5252))
                    : const Color(0xFF1E2D48),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_active_rounded,
                            color: _canSubmit ? Colors.black87 : const Color(0xFF3A5070),
                            size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Set Alert',
                          style: TextStyle(
                            color: _canSubmit ? Colors.black87 : const Color(0xFF3A5070),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF6C63FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF4A6080),
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _directionButton(String value, String label, Color color) {
    final isSelected = _direction == value;
    return GestureDetector(
      onTap: () => setState(() {
        _direction = value;
        _selectedPct = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : const Color(0xFF131929),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF1E2D48),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : const Color(0xFF4A6080),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── Daftar alert aktif & triggered ────────────────────────
  Widget _buildAlertList() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF), strokeWidth: 2));
    }

    final active    = _alerts.where((a) => a.status == 'active').toList();
    final triggered = _alerts.where((a) => a.status == 'triggered').toList();

    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Icon(Icons.notifications_off_rounded, color: const Color(0xFF1E2D48), size: 48),
            const SizedBox(height: 12),
            const Text('Belum ada alert',
                style: TextStyle(color: Color(0xFF3A5070), fontSize: 14)),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active.isNotEmpty) ...[
            _sectionLabel('🔔  AKTIF  (${active.length})', const Color(0xFF6C63FF)),
            const SizedBox(height: 8),
            ...active.map((a) => _alertTile(a)),
            const SizedBox(height: 20),
          ],
          if (triggered.isNotEmpty) ...[
            _sectionLabel('✅  SUDAH TERCAPAI', const Color(0xFF4A6080)),
            const SizedBox(height: 8),
            ...triggered.map((a) => _alertTile(a)),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Text(text,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2));
  }

  Widget _alertTile(_Alert alert) {
    final isActive  = alert.status == 'active';
    final isUp      = alert.direction == 'up';
    final color     = isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252);
    final livePrice = widget.livePrices[alert.coinSymbol];

    // Hitung jarak ke target
    String distanceText = '';
    if (livePrice != null && livePrice > 0) {
      final diff = ((alert.targetPrice - livePrice) / livePrice * 100);
      distanceText = '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}% dari sekarang';
    }

    final coinConfig = _coins.firstWhere(
      (c) => c.symbol == alert.coinSymbol,
      orElse: () => _coins[0],
    );

    return Dismissible(
      key: Key('alert_${alert.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5252).withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252)),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0D1427),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Hapus Alert?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            content: Text(
              'Alert ${alert.coinSymbol} \$${_fmtPrice(alert.targetPrice)} akan dihapus.',
              style: const TextStyle(color: Color(0xFF6C8EBF)),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF6C8EBF)))),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Hapus', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _deleteAlert(alert.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1427),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? const Color(0xFF1E2D48) : const Color(0xFF131929),
          ),
        ),
        child: Row(
          children: [
            // Coin badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: coinConfig.gradient
                        .map((c) => c.withOpacity(isActive ? 1.0 : 0.4))
                        .toList()),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(coinConfig.emoji,
                  style: TextStyle(
                      color: isActive ? Colors.white : Colors.white54,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        alert.coinSymbol,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(isActive ? 0.12 : 0.05),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                              color: isActive ? color : color.withOpacity(0.4),
                              size: 11,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              isUp ? 'Naik' : 'Turun',
                              style: TextStyle(
                                  color: isActive ? color : color.withOpacity(0.4),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Target: \$${_fmtPrice(alert.targetPrice)}',
                    style: TextStyle(
                      color: isActive ? const Color(0xFFB0BEC5) : const Color(0xFF3A5070),
                      fontSize: 12,
                    ),
                  ),
                  if (distanceText.isNotEmpty && isActive)
                    Text(distanceText,
                        style: const TextStyle(
                            color: Color(0xFF4A6080), fontSize: 10)),
                ],
              ),
            ),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF6C63FF).withOpacity(0.12)
                    : const Color(0xFF00E676).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? '🔔 Aktif' : '✅ Tercapai',
                style: TextStyle(
                  color: isActive ? const Color(0xFF9D97FF) : const Color(0xFF2E7D32),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtPrice(double v) {
    if (v >= 10000) {
      return v
          .toStringAsFixed(0)
          .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    }
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }
}