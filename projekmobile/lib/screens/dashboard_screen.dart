import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import '../service/api_config.dart';

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────
class _AssetItem {
  final String name;
  final String symbol;
  final String pair;
  final double priceUsd;
  final double? prevPriceUsd; // untuk flash animasi naik/turun

  const _AssetItem({
    required this.name,
    required this.symbol,
    required this.pair,
    required this.priceUsd,
    this.prevPriceUsd,
  });

  _AssetItem copyWithPrev(double prev) => _AssetItem(
    name: name,
    symbol: symbol,
    pair: pair,
    priceUsd: priceUsd,
    prevPriceUsd: prev,
  );
}

// ─────────────────────────────────────────────
// TIMEZONE DATA
// ─────────────────────────────────────────────
class _TimezoneOption {
  final String label;
  final String city;
  final int offsetHours;
  final int offsetMinutes;

  const _TimezoneOption({
    required this.label,
    required this.city,
    required this.offsetHours,
    this.offsetMinutes = 0,
  });

  DateTime now() {
    final utc = DateTime.now().toUtc();
    return utc.add(Duration(hours: offsetHours, minutes: offsetMinutes));
  }
}

const List<_TimezoneOption> _timezones = [
  _TimezoneOption(label: 'WIB', city: 'Jakarta', offsetHours: 7),
  _TimezoneOption(label: 'WITA', city: 'Makassar', offsetHours: 8),
  _TimezoneOption(label: 'WIT', city: 'Jayapura', offsetHours: 9),
  _TimezoneOption(label: 'UTC', city: 'London', offsetHours: 0),
  _TimezoneOption(label: 'EST', city: 'New York', offsetHours: -5),
  _TimezoneOption(label: 'CST', city: 'Chicago', offsetHours: -6),
  _TimezoneOption(label: 'PST', city: 'Los Angeles', offsetHours: -8),
  _TimezoneOption(label: 'CET', city: 'Paris', offsetHours: 1),
  _TimezoneOption(
    label: 'IST',
    city: 'Mumbai',
    offsetHours: 5,
    offsetMinutes: 30,
  ),
  _TimezoneOption(label: 'SGT', city: 'Singapore', offsetHours: 8),
  _TimezoneOption(label: 'JST', city: 'Tokyo', offsetHours: 9),
  _TimezoneOption(label: 'AEST', city: 'Sydney', offsetHours: 10),
];

// ─────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  // Interval fetch harga (lebih cepat = lebih real-time)
  static const Duration _priceRefreshInterval = Duration(milliseconds: 2000);

  // ── State ──────────────────────────────────
  bool _isPrivacyMode = false;
  double _totalBalance = 950.0;
  bool _isLoadingPrices = true;
  bool _isFetchingPrices = false;
  bool _hasPendingPriceFetch = false;
  String? _priceError;
  String? _lastUpdatedAt;
  List<_AssetItem> _assets = const [];
  _TimezoneOption _selectedTimezone = _timezones[0]; // Default WIB
  String _clockDisplay = '';
  String _dateDisplay = '';

  // ── Timers & Subscriptions ─────────────────
  Timer? _priceRefreshTimer;
  Timer? _clockTimer;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  DateTime _lastShakeTime = DateTime.now();

  // ── Animation ─────────────────────────────
  late AnimationController _pulseController;
  // Map symbol -> flash color (green/red)
  final Map<String, Color?> _flashColors = {};
  final Map<String, Timer?> _flashTimers = {};

  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _startClock();
    _startShakeDetection();
    _requestPriceFetch(showLoader: true);

    _priceRefreshTimer = Timer.periodic(_priceRefreshInterval, (_) {
      _requestPriceFetch(showLoader: false);
    });
  }

  // ─────────────────────────────────────────────
  // JAM REAL-TIME
  // ─────────────────────────────────────────────
  void _startClock() {
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
  }

  void _updateClock() {
    if (!mounted) return;
    final now = _selectedTimezone.now();
    setState(() {
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final ss = now.second.toString().padLeft(2, '0');
      _clockDisplay = '$hh:$mm:$ss';

      const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      _dateDisplay =
          '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
    });
  }

  void _onTimezoneChanged(_TimezoneOption tz) {
    setState(() => _selectedTimezone = tz);
    _updateClock();
  }

  // ─────────────────────────────────────────────
  // PRICE FETCH — FIX REAL-TIME
  // Strategi: queue + debounce agar tidak overlap
  // ─────────────────────────────────────────────
  void _requestPriceFetch({required bool showLoader}) {
    if (_isFetchingPrices) {
      _hasPendingPriceFetch = true;
      return;
    }
    _fetchCryptoPrices(showLoader: showLoader);
  }

  Future<void> _fetchCryptoPrices({bool showLoader = true}) async {
    _isFetchingPrices = true;

    if (showLoader && mounted) {
      setState(() {
        _isLoadingPrices = true;
        _priceError = null;
      });
    }

    try {
      final response = await http
          .get(Uri.parse(ApiConfig.endpoint('/crypto/prices')))
          .timeout(
            const Duration(seconds: 5),
          ); // Timeout agar tidak nunggu lama

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> jsonMap = jsonDecode(response.body);
      final List<dynamic> assets = (jsonMap['data'] as List<dynamic>? ?? []);
      final updatedAt = jsonMap['updatedAt']?.toString();

      final nextAssets = <_AssetItem>[];
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name']?.toString();
        final symbol = asset['symbol']?.toString();
        final pair = asset['pair']?.toString();
        final price = num.tryParse(asset['price']?.toString() ?? '');
        if (name == null || symbol == null || pair == null || price == null)
          continue;

        // Cari harga lama untuk flash
        final prev = _assets
            .where((a) => a.symbol == symbol)
            .map((a) => a.priceUsd)
            .firstOrNull;

        final item = _AssetItem(
          name: name,
          symbol: symbol,
          pair: pair,
          priceUsd: price.toDouble(),
          prevPriceUsd: prev,
        );
        nextAssets.add(item);

        // Trigger flash jika harga berubah
        if (prev != null && prev != price.toDouble()) {
          _triggerFlash(symbol, price.toDouble() > prev);
        }
      }

      if (!mounted) return;
      setState(() {
        _assets = nextAssets;
        _lastUpdatedAt = updatedAt;
        _priceError = assets.isNotEmpty && nextAssets.isEmpty
            ? 'Format data aset tidak sesuai'
            : null;
        _isLoadingPrices = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _priceError = 'Koneksi timeout, mencoba lagi...';
        _isLoadingPrices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _priceError = 'Harga realtime belum tersedia';
        _isLoadingPrices = false;
      });
    } finally {
      _isFetchingPrices = false;
      if (_hasPendingPriceFetch) {
        _hasPendingPriceFetch = false;
        _requestPriceFetch(showLoader: false);
      }
    }
  }

  void _triggerFlash(String symbol, bool isUp) {
    _flashTimers[symbol]?.cancel();
    setState(
      () => _flashColors[symbol] = isUp ? Colors.greenAccent : Colors.redAccent,
    );
    _flashTimers[symbol] = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashColors[symbol] = null);
    });
  }

  // ─────────────────────────────────────────────
  // SHAKE DETECTION
  // ─────────────────────────────────────────────
  void _startShakeDetection() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS))
      return;

    _accelerometerSubscription = userAccelerometerEvents.listen((
      UserAccelerometerEvent event,
    ) {
      final gForce = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (gForce > 12) {
        final now = DateTime.now();
        if (now.difference(_lastShakeTime).inMilliseconds > 1500) {
          _lastShakeTime = now;
          setState(() => _isPrivacyMode = !_isPrivacyMode);
        }
      }
    }, onError: (_) {});
  }

  // ─────────────────────────────────────────────
  @override
  void dispose() {
    _pulseController.dispose();
    _priceRefreshTimer?.cancel();
    _clockTimer?.cancel();
    _accelerometerSubscription?.cancel();
    for (final t in _flashTimers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // HELPERS FORMAT
  // ─────────────────────────────────────────────
  String _formatUsd(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final wholeWithCommas = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '\$$wholeWithCommas.${parts[1]}';
  }

  String _formatUpdatedTime(String isoTime) {
    final dt = DateTime.tryParse(isoTime)?.toLocal();
    if (dt == null) return '-';
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPortfolioCard(),
              const SizedBox(height: 24),
              _buildAssetsHeader(),
              const SizedBox(height: 12),
              Expanded(child: _buildAssetList()),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // APP BAR dengan jam & timezone
  // ─────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final isCompact = MediaQuery.of(context).size.width < 390;

    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1117), Color(0xFF161B2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border(
            bottom: BorderSide(color: Color(0xFF1E2740), width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Kiri: Logo / judul
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3BC8E7)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.currency_bitcoin,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Jaga Lilin',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Text(
                              'Live Market',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFF6C8EBF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Kanan: Jam + Timezone selector
                const SizedBox(width: 8),
                Flexible(child: _buildClockWidget(isCompact: isCompact)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClockWidget({required bool isCompact}) {
    return GestureDetector(
      onTap: _showTimezoneBottomSheet,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: isCompact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A3A5E), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCompact)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _clockDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _selectedTimezone.label,
                      style: const TextStyle(
                        color: Color(0xFF8B85FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _clockDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: 1,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _dateDisplay,
                        style: const TextStyle(
                          color: Color(0xFF6C8EBF),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _selectedTimezone.label,
                          style: const TextStyle(
                            color: Color(0xFF8B85FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, color: Color(0xFF6C8EBF), size: 16),
          ],
        ),
      ),
    );
  }

  void _showTimezoneBottomSheet() {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = min(screenHeight * 0.75, 520.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A5E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih Zona Waktu',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _timezones.length,
                  itemBuilder: (_, index) {
                    final tz = _timezones[index];
                    final isSelected = tz.label == _selectedTimezone.label;
                    return ListTile(
                      dense: true,
                      onTap: () {
                        Navigator.pop(context);
                        _onTimezoneChanged(tz);
                      },
                      leading: Container(
                        width: 44,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6C63FF).withOpacity(0.25)
                              : const Color(0xFF1A2035),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6C63FF)
                                : const Color(0xFF2A3A5E),
                          ),
                        ),
                        child: Text(
                          tz.label,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF8B85FF)
                                : const Color(0xFF6C8EBF),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        tz.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFFB0BEC5),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        'UTC${tz.offsetHours >= 0 ? '+' : ''}${tz.offsetHours}'
                        '${tz.offsetMinutes > 0 ? ':${tz.offsetMinutes.toString().padLeft(2, '0')}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4A5C7A),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF6C63FF),
                              size: 20,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PORTFOLIO CARD
  // ─────────────────────────────────────────────
  Widget _buildPortfolioCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1060), Color(0xFF0D2550), Color(0xFF0A1628)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3A6E).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Portofolio',
                style: TextStyle(
                  color: Color(0xFF8899BB),
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _isPrivacyMode = !_isPrivacyMode),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isPrivacyMode
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: const Color(0xFF8899BB),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isPrivacyMode ? '\$  •••••••••' : _formatUsd(_totalBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          // Badge perubahan
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C853).withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      color: Color(0xFF00E676),
                      size: 12,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '\$15.30  (1.6%)',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Hari ini',
                style: TextStyle(color: Color(0xFF4A5C7A), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Hint shake
          Row(
            children: [
              const Icon(Icons.vibration, color: Color(0xFF4A5C7A), size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Ketuk ikon mata atau goyangkan HP untuk sembunyikan saldo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF4A5C7A).withOpacity(0.8),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ASSETS HEADER
  // ─────────────────────────────────────────────
  Widget _buildAssetsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'TOP ASSETS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        Row(
          children: [
            // Live indicator
            if (!_isLoadingPrices && _priceError == null)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(
                          const Color(0xFF00E676),
                          const Color(0xFF00C853).withOpacity(0.3),
                          _pulseController.value,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF00E676,
                            ).withOpacity(0.4 * (1 - _pulseController.value)),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            if (_lastUpdatedAt != null) ...[
              const SizedBox(width: 10),
              Text(
                _formatUpdatedTime(_lastUpdatedAt!),
                style: const TextStyle(color: Color(0xFF4A5C7A), fontSize: 11),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // ASSET LIST
  // ─────────────────────────────────────────────
  Widget _buildAssetList() {
    if (_isLoadingPrices && _assets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF6C63FF)),
            SizedBox(height: 12),
            Text(
              'Mengambil harga real-time...',
              style: TextStyle(color: Color(0xFF4A5C7A)),
            ),
          ],
        ),
      );
    }

    if (_priceError != null && _assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Color(0xFF4A5C7A),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _priceError!,
              style: const TextStyle(color: Color(0xFF6C8EBF)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _requestPriceFetch(showLoader: true),
              icon: const Icon(Icons.refresh, color: Color(0xFF6C63FF)),
              label: const Text(
                'Coba lagi',
                style: TextStyle(color: Color(0xFF6C63FF)),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _assets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildAssetTile(_assets[index]),
    );
  }

  // ─────────────────────────────────────────────
  // ASSET TILE dengan flash animasi
  // ─────────────────────────────────────────────
  Widget _buildAssetTile(_AssetItem asset) {
    final flashColor = _flashColors[asset.symbol];
    final prev = asset.prevPriceUsd;
    final isUp = prev == null || asset.priceUsd >= prev;

    final priceColor = prev == null || prev == asset.priceUsd
        ? Colors.white
        : (isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: flashColor != null
            ? flashColor.withOpacity(0.08)
            : const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: flashColor != null
              ? flashColor.withOpacity(0.4)
              : const Color(0xFF1E2740),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _gradientForSymbol(asset.symbol),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              asset.symbol.length > 2 ? asset.symbol[0] : asset.symbol,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Nama & pair
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  asset.pair,
                  style: const TextStyle(
                    color: Color(0xFF4A5C7A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Harga + perubahan
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: priceColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: Text(_formatUsd(asset.priceUsd)),
              ),
              if (prev != null && prev != asset.priceUsd)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: isUp
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252),
                      size: 16,
                    ),
                    Text(
                      '\$${(asset.priceUsd - prev).abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isUp
                            ? const Color(0xFF00E676)
                            : const Color(0xFFFF5252),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Color> _gradientForSymbol(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return [const Color(0xFFF7931A), const Color(0xFFFFB74D)];
      case 'ETH':
        return [const Color(0xFF627EEA), const Color(0xFF3BC8E7)];
      case 'BNB':
        return [const Color(0xFFF3BA2F), const Color(0xFFFDD835)];
      case 'SOL':
        return [const Color(0xFF9945FF), const Color(0xFF14F195)];
      default:
        return [const Color(0xFF6C63FF), const Color(0xFF3BC8E7)];
    }
  }
}
