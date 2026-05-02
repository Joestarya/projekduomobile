import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import '../service/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────
class _AssetItem {
  final String name;
  final String symbol;
  final String pair;
  final double priceUsd;
  final double? prevPriceUsd;
  final double changePercent; // % perubahan 24h
  final List<double> sparkline; // data mini chart

  const _AssetItem({
    required this.name,
    required this.symbol,
    required this.pair,
    required this.priceUsd,
    this.prevPriceUsd,
    this.changePercent = 0.0,
    this.sparkline = const [],
  });

  _AssetItem copyWithPrev(double prev) => _AssetItem(
    name: name,
    symbol: symbol,
    pair: pair,
    priceUsd: priceUsd,
    prevPriceUsd: prev,
    changePercent: changePercent,
    sparkline: sparkline,
  );
}

// ─────────────────────────────────────────────
// SPARKLINE PAINTER (Mini Chart seperti Stockbit)
// ─────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final bool isUp;

  const _SparklinePainter({required this.data, required this.isUp});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final range = (maxVal - minVal).abs();
    if (range == 0) return;

    final upColor = const Color(0xFF00E676);
    final downColor = const Color(0xFFFF5252);
    final lineColor = isUp ? upColor : downColor;
    final fillColor = isUp
        ? const Color(0xFF00E676).withOpacity(0.15)
        : const Color(0xFFFF5252).withOpacity(0.15);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final normalized = (data[i] - minVal) / range;
      final y =
          size.height -
          (normalized * size.height * 0.85) -
          (size.height * 0.075);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        // Smooth curve dengan cubic bezier
        final prevX = ((i - 1) / (data.length - 1)) * size.width;
        final prevNorm = (data[i - 1] - minVal) / range;
        final prevY =
            size.height -
            (prevNorm * size.height * 0.85) -
            (size.height * 0.075);
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
        fillPath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }

    // Tutup fill path ke bawah
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Titik di ujung kanan (harga sekarang)
    final lastX = size.width;
    final lastNorm = (data.last - minVal) / range;
    final lastY =
        size.height - (lastNorm * size.height * 0.85) - (size.height * 0.075);
    canvas.drawCircle(Offset(lastX, lastY), 2.5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.isUp != isUp;
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
  static const Duration _priceRefreshInterval = Duration(milliseconds: 2000);
  static const Duration _chartRefreshInterval = Duration(minutes: 5);

  // ── State ──────────────────────────────────
  bool _isPrivacyMode = false;
  bool _isIdrMode = true;
  double _totalBalance = 0.0;
  Map<String, double> _userBalances = {};
  bool _isPortfolioConnected = false;
  bool _isLoadingPrices = true;
  bool _isFetchingPrices = false;
  bool _hasPendingPriceFetch = false;
  String? _priceError;
  String? _lastUpdatedAt;
  List<_AssetItem> _assets = const [];
  _TimezoneOption _selectedTimezone = _timezones[0];
  String _clockDisplay = '';
  String _dateDisplay = '';

  // Sparkline data cache per symbol
  final Map<String, List<double>> _sparklineCache = {};

  // ── Timers & Subscriptions ─────────────────
  Timer? _priceRefreshTimer;
  Timer? _chartRefreshTimer;
  Timer? _clockTimer;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  DateTime _lastShakeTime = DateTime.now();

  // ── Animation ─────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _cardSlideController;
  late Animation<double> _cardSlideAnimation;
  final Map<String, Color?> _flashColors = {};
  final Map<String, Timer?> _flashTimers = {};

  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _cardSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _cardSlideAnimation = CurvedAnimation(
      parent: _cardSlideController,
      curve: Curves.easeOutCubic,
    );

    _startClock();
    _startShakeDetection();
    _requestPriceFetch(showLoader: true);
    _fetchAllSparklines();
    _fetchPortfolio();

    _priceRefreshTimer = Timer.periodic(_priceRefreshInterval, (_) {
      _requestPriceFetch(showLoader: false);
    });
    _chartRefreshTimer = Timer.periodic(_chartRefreshInterval, (_) {
      _fetchAllSparklines();
      _fetchPortfolio();
    });

    // Animasi masuk
    Future.delayed(const Duration(milliseconds: 200), () {
      _cardSlideController.forward();
    });
  }

  // ─────────────────────────────────────────────
  // CLOCK
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
      _clockDisplay =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

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
  // SPARKLINE FETCH — dari Binance Kline API
  // ─────────────────────────────────────────────
  Future<void> _fetchAllSparklines() async {
    final symbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
    for (final sym in symbols) {
      _fetchSparkline(sym);
    }
  }

  Future<void> _fetchSparkline(String symbol) async {
    // Coba dari backend dulu, fallback ke Binance langsung
    try {
      // Coba endpoint backend custom
      final backendUrl = ApiConfig.endpoint(
        '/crypto/klines?symbol=$symbol&interval=1h&limit=24',
      );
      final resp = await http
          .get(Uri.parse(backendUrl))
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final List<dynamic> klines = json['data'] ?? [];
        if (klines.isNotEmpty) {
          final prices = klines
              .map<double>((k) => double.tryParse(k['close'].toString()) ?? 0)
              .toList();
          if (mounted) setState(() => _sparklineCache[symbol] = prices);
          return;
        }
      }
    } catch (_) {}

    // Fallback: langsung ke Binance public API
    try {
      final binanceUrl =
          'https://data-api.binance.vision/api/v3/klines?symbol=$symbol&interval=1h&limit=24';
      final resp = await http
          .get(Uri.parse(binanceUrl))
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final List<dynamic> klines = jsonDecode(resp.body);
        // Binance kline format: [openTime, open, high, low, close, ...]
        final prices = klines.map<double>((k) {
          return double.tryParse(k[4].toString()) ?? 0; // index 4 = close price
        }).toList();

        if (mounted && prices.isNotEmpty) {
          setState(() => _sparklineCache[symbol] = prices);
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────
  // PORTFOLIO FETCH
  // ─────────────────────────────────────────────
  Future<void> _fetchPortfolio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) return;

      final url = ApiConfig.endpoint('/crypto/portfolio?user_id=$userId');
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final balancesList = data['balances'] as List;

        final Map<String, double> newBalances = {};
        for (var b in balancesList) {
          final asset = b['asset'];
          final free = double.tryParse(b['free'].toString()) ?? 0.0;
          final locked = double.tryParse(b['locked'].toString()) ?? 0.0;
          newBalances[asset] = free + locked;
        }

        if (mounted) {
          setState(() {
            _isPortfolioConnected = true;
            _userBalances = newBalances;
            _calculateTotalBalance();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isPortfolioConnected = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPortfolioConnected = false;
        });
      }
    }
  }

  double _getIdrRate() {
    final idrAsset = _assets.where((a) => a.symbol == 'USDT_IDR').firstOrNull;
    return idrAsset?.priceUsd ?? 17333.0;
  }

  void _calculateTotalBalance() {
    double total = 0.0;
    for (var entry in _userBalances.entries) {
      final asset = entry.key;
      final amount = entry.value;

      if (asset == 'USDT' || asset == 'USDC' || asset == 'FDUSD' || asset == 'BUSD') {
        total += amount;
      } else if (asset == 'IDR' || asset == 'BIDR' || asset == 'IDRT') {
        total += amount / _getIdrRate();
      } else {
        final assetItem = _assets.where((a) => a.symbol == asset).firstOrNull;
        if (assetItem != null) {
          total += amount * assetItem.priceUsd;
        }
      }
    }

    if (_userBalances.isNotEmpty) {
      _totalBalance = total;
    }
  }

  // ─────────────────────────────────────────────
  // PRICE FETCH
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
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200)
        throw Exception('HTTP ${response.statusCode}');

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
        final changePct =
            num.tryParse(asset['changePercent']?.toString() ?? '0') ?? 0;
        if (name == null || symbol == null || pair == null || price == null)
          continue;

        final prev = _assets
            .where((a) => a.symbol == symbol)
            .map((a) => a.priceUsd)
            .firstOrNull;

        // Ambil sparkline dari cache, pakai pair sebagai key (e.g. BTCUSDT)
        final sparkline = _sparklineCache[pair] ?? [];

        final item = _AssetItem(
          name: name,
          symbol: symbol,
          pair: pair,
          priceUsd: price.toDouble(),
          prevPriceUsd: prev,
          changePercent: changePct.toDouble(),
          sparkline: sparkline,
        );
        nextAssets.add(item);

        if (prev != null && prev != price.toDouble()) {
          _triggerFlash(symbol, price.toDouble() > prev);
        }
      }

      if (!mounted) return;
      setState(() {
        _assets = nextAssets;
        _lastUpdatedAt = updatedAt;
        _priceError = null;
        _isLoadingPrices = false;
        _calculateTotalBalance();
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
    _cardSlideController.dispose();
    _priceRefreshTimer?.cancel();
    _chartRefreshTimer?.cancel();
    _clockTimer?.cancel();
    _accelerometerSubscription?.cancel();
    for (final t in _flashTimers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // FORMAT HELPERS
  // ─────────────────────────────────────────────
  String _formatUsd(double value) {
    if (value >= 10000) {
      final fixed = value.toStringAsFixed(0);
      return '\$${fixed.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    } else if (value >= 1) {
      return '\$${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    } else {
      return '\$${value.toStringAsFixed(4)}';
    }
  }

  String _formatIdr(double value) {
    final fixed = value.toStringAsFixed(0);
    return 'Rp ${fixed.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';
  }

  String _formatUpdatedTime(String isoTime) {
    final dt = DateTime.tryParse(isoTime)?.toLocal();
    if (dt == null) return '-';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatChangePercent(double pct) {
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(2)}%';
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.15),
                end: Offset.zero,
              ).animate(_cardSlideAnimation),
              child: FadeTransition(
                opacity: _cardSlideAnimation,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _buildPortfolioCard(),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildAssetsHeader(),
            ),
            const SizedBox(height: 8),
            // Divider
            Container(height: 1, color: Theme.of(context).dividerTheme.color),
            // List
            Expanded(child: _buildAssetList()),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final isCompact = MediaQuery.of(context).size.width < 390;
    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).appBarTheme.backgroundColor,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? Colors.transparent, width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Logo
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.currency_bitcoin,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Jaga Lilin',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00E676),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Live Market',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                // Clock
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
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerTheme.color ?? Colors.transparent, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max, // ⬅️ IMPORTANT
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _clockDisplay,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15, // ⬅️ sedikit kecil
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),

                  if (!isCompact)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _dateDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF4A6080),
                                fontSize: 9, // ⬅️ kecilkan
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _selectedTimezone.label,
                              style: const TextStyle(
                                color: Color(0xFF9D97FF),
                                fontSize: 8, // ⬅️ kecilkan
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF4A6080),
              size: 16,
            ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A5E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
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
                  padding: const EdgeInsets.only(bottom: 16),
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
                        width: 46,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6C63FF).withOpacity(0.2)
                              : const Color(0xFF131929),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6C63FF)
                                : const Color(0xFF1E2D48),
                          ),
                        ),
                        child: Text(
                          tz.label,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF9D97FF)
                                : const Color(0xFF4A6080),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Text(
                        tz.city,
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
                        style: const TextStyle(
                          color: Color(0xFF2E4060),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).primaryColor.withOpacity(0.8), Theme.of(context).cardTheme.color!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.12),
            blurRadius: 24,
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
                  color: Color(0xFFFFFFFF),
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              
              GestureDetector(
                onTap: () => setState(() => _isPrivacyMode = !_isPrivacyMode),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isPrivacyMode
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: const Color(0xFF7A90B0),
                    size: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isPrivacyMode
                ? '•••••••••'
                : (!_isPortfolioConnected
                    ? 'Data tidak tersedia'
                    : (_isIdrMode ? _formatIdr(_totalBalance * _getIdrRate()) : _formatUsd(_totalBalance))),
            style: TextStyle(
              color: !_isPortfolioConnected && !_isPrivacyMode ? Colors.white70 : Colors.white,
              fontSize: !_isPortfolioConnected && !_isPrivacyMode ? 22 : 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
        
          const SizedBox(height: 12),
          // Quick Stats Row
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._userBalances.entries
                        .where((e) => e.value > 0)
                        .map((e) {
                          double valueIdr = 0.0;
                          double valueUsd = 0.0;
                          if (e.key == 'IDR' || e.key == 'BIDR' || e.key == 'IDRT') {
                            valueIdr = e.value;
                            valueUsd = e.value / _getIdrRate();
                          } else if (e.key == 'USDT' || e.key == 'USDC' || e.key == 'BUSD' || e.key == 'FDUSD') {
                            valueIdr = e.value * _getIdrRate();
                            valueUsd = e.value;
                          } else {
                            final asset = _assets.where((a) => a.symbol == e.key).firstOrNull;
                            final priceUsd = asset?.priceUsd ?? 0.0;
                            valueIdr = e.value * priceUsd * _getIdrRate();
                            valueUsd = e.value * priceUsd;
                          }
                          
                          String displayStr;
                          if (_isPrivacyMode) {
                            displayStr = _isIdrMode ? 'Rp •••' : '\$ •••';
                          } else {
                            displayStr = _isIdrMode ? _formatIdr(valueIdr) : _formatUsd(valueUsd);
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _buildQuickStat(e.key, displayStr),
                          );
                        }),
                      if (_userBalances.isEmpty || !_userBalances.values.any((v) => v > 0))
                         _buildQuickStat('Aset', 'Kosong'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.vibration_rounded,
                    color: Color(0xFF3A5070),
                    size: 11,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Goyangkan untuk\nmembunyikan',
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color.fromARGB(255, 252, 253, 255).withOpacity(0.9),
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
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

  Widget _buildQuickStat(String symbol, String displayValue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: const TextStyle(
              color: Color(0xFF6C8EBF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            displayValue,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
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
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      IconButton(
        icon: const Icon(Icons.currency_exchange, color: Colors.white70),
        onPressed: () {
          setState(() {
            _isIdrMode = !_isIdrMode;
          });
        },
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
            CircularProgressIndicator(color: Color(0xFF6C63FF), strokeWidth: 2),
            SizedBox(height: 16),
            Text(
              'Mengambil data pasar...',
              style: TextStyle(color: Color(0xFF4A6080), fontSize: 13),
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
            Icon(
              Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
              color: const Color(0xFF3A5070),
              size: 44,
            ),
            const SizedBox(height: 14),
            Text(
              _priceError!,
              style: const TextStyle(color: Color(0xFF6C8EBF), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => _requestPriceFetch(showLoader: true),
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6C63FF)),
              label: const Text(
                'Coba lagi',
                style: TextStyle(color: Color(0xFF6C63FF)),
              ),
            ),
          ],
        ),
      );
    }

    final displayAssets = _assets.where((a) => a.symbol != 'USDT_IDR').toList();
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: displayAssets.length,
      itemBuilder: (context, index) {
        // Staggered animation per item
        return AnimatedBuilder(
          animation: _cardSlideAnimation,
          builder: (context, child) {
            final delay = (index * 0.15).clamp(0.0, 1.0);
            final animValue =
                (((_cardSlideAnimation.value - delay) / (1 - delay)).clamp(
                  0.0,
                  1.0,
                ));
            return Transform.translate(
              offset: Offset(0, 20 * (1 - animValue)),
              child: Opacity(opacity: animValue, child: child),
            );
          },
          child: _buildAssetTile(displayAssets[index]),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // ASSET TILE — Mirip Stockbit dengan mini chart
  // ─────────────────────────────────────────────
  Widget _buildAssetTile(_AssetItem asset) {
    final flashColor = _flashColors[asset.symbol];
    final prev = asset.prevPriceUsd;
    final isUp = asset.changePercent >= 0;

    // Warna harga berdasarkan flash atau % perubahan
    final priceColor = flashColor != null
        ? (flashColor == Colors.greenAccent
              ? const Color(0xFF00E676)
              : const Color(0xFFFF5252))
        : (isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252));

    // Sparkline — gunakan dari cache atau data dummy
    final sparkData = _sparklineCache[asset.pair];
    final hasChart = sparkData != null && sparkData.length > 2;

    final userBalance = _userBalances[asset.symbol] ?? 0.0;

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (_) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _OrderBottomSheet(asset: asset, userBalance: userBalance),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: flashColor != null
            ? flashColor.withOpacity(0.04)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? Colors.transparent, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            // ── Avatar ──
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _gradientForSymbol(asset.symbol),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                asset.symbol.length > 2 ? asset.symbol[0] : asset.symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Nama & Pair ──
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.symbol,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    userBalance > 0
                        ? '${userBalance.toStringAsFixed(userBalance < 1 ? 4 : 2)} ${asset.symbol}'
                        : asset.name,
                    style: TextStyle(
                      color: userBalance > 0 ? const Color(0xFF6C63FF) : const Color(0xFF4A6080),
                      fontSize: 12,
                      fontWeight: userBalance > 0 ? FontWeight.w600 : FontWeight.normal,
                      overflow: TextOverflow.ellipsis,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),

            // ── Mini Chart (Sparkline) ──
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 44,
                  child: hasChart
                      ? CustomPaint(
                          painter: _SparklinePainter(
                            data: sparkData!,
                            isUp: isUp,
                          ),
                        )
                      : _buildLoadingChart(isUp),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // ── Harga & % — lebar tetap agar tidak overflow ──
            SizedBox(
              width: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      color: priceColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -0.3,
                    ),
                    child: Text(
                      _formatUsd(asset.priceUsd),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isUp
                          ? const Color(0xFF00E676).withOpacity(0.12)
                          : const Color(0xFFFF5252).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          isUp
                              ? Icons.arrow_drop_up_rounded
                              : Icons.arrow_drop_down_rounded,
                          color: isUp
                              ? const Color(0xFF00E676)
                              : const Color(0xFFFF5252),
                          size: 13,
                        ),
                        Flexible(
                          child: Text(
                            _formatChangePercent(asset.changePercent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUp
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFF5252),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            // ── Trade Icon ──
            Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white.withOpacity(0.5),
              size: 20,
            ),
          ],
        ),
        ),
      ),
    );
  }

  // Chart placeholder saat loading
  Widget _buildLoadingChart(bool isUp) {
    return Center(
      child: LinearProgressIndicator(
        backgroundColor: const Color(0xFF1A2035),
        valueColor: AlwaysStoppedAnimation<Color>(
          isUp
              ? const Color(0xFF00E676).withOpacity(0.25)
              : const Color(0xFFFF5252).withOpacity(0.25),
        ),
      ),
    );
  }

  List<Color> _gradientForSymbol(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return [const Color(0xFFFF9800), const Color(0xFFFFB74D)];
      case 'ETH':
        return [const Color(0xFF627EEA), const Color(0xFF8BA4F7)];
      case 'BNB':
        return [const Color(0xFFF3BA2F), const Color(0xFFFFE082)];
      case 'SOL':
        return [const Color(0xFF9945FF), const Color(0xFF19FB9B)];
      case 'XRP':
        return [const Color(0xFF0F6FDE), const Color(0xFF3BC8E7)];
      case 'ADA':
        return [const Color(0xFF0033AD), const Color(0xFF0D6EFF)];
      default:
        return [const Color(0xFF6C63FF), const Color(0xFF3BC8E7)];
    }
  }
}

// ─────────────────────────────────────────────
// ORDER BOTTOM SHEET
// ─────────────────────────────────────────────
class _OrderBottomSheet extends StatefulWidget {
  final _AssetItem asset;
  final double userBalance;

  const _OrderBottomSheet({required this.asset, required this.userBalance});

  @override
  State<_OrderBottomSheet> createState() => _OrderBottomSheetState();
}

class _OrderBottomSheetState extends State<_OrderBottomSheet> {
  bool isBuy = true;
  final TextEditingController _amountController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  Future<void> _submitOrder() async {
    final amountText = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(amountText) ?? 0.0;
    if (amount <= 0) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      final body = {
        'user_id': userId,
        'symbol': widget.asset.pair,
        'side': isBuy ? 'BUY' : 'SELL',
        'type': 'MARKET',
      };

      if (isBuy) {
        body['quoteOrderQty'] = amount.toString();
      } else {
        body['quantity'] = amount.toString();
      }

      final response = await http.post(
        Uri.parse(ApiConfig.endpoint('/crypto/order')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final respData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _successMessage = 'Transaksi berhasil dikonfirmasi!';
        });
        
        // Tutup bottom sheet setelah sukses
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = respData['detail'] ?? respData['message'] ?? 'Terjadi kesalahan tidak dikenal.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error Jaringan. Pastikan Anda terkoneksi ke Internet dan tidak diblokir ISP.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Trading ${widget.asset.symbol}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Saldo: ${widget.userBalance.toStringAsFixed(4)} ${widget.asset.symbol}',
                style: const TextStyle(
                  color: Color(0xFF8B9BB4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => isBuy = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isBuy ? const Color(0xFF00E676) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isBuy ? Colors.transparent : const Color(0xFF3A5070),
                      ),
                    ),
                    child: Text(
                      'BUY',
                      style: TextStyle(
                        color: isBuy ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => isBuy = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: !isBuy ? const Color(0xFFFF5252) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !isBuy ? Colors.transparent : const Color(0xFF3A5070),
                      ),
                    ),
                    child: Text(
                      'SELL',
                      style: TextStyle(
                        color: !isBuy ? Colors.white : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              labelText: isBuy ? 'Jumlah USDT' : 'Jumlah ${widget.asset.symbol}',
              labelStyle: const TextStyle(color: Color(0xFF8B9BB4)),
              filled: true,
              fillColor: const Color(0xFF131929),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixText: isBuy ? 'USDT' : widget.asset.symbol,
              suffixStyle: const TextStyle(color: Colors.white),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.15),
                border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (_successMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.15),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: Color(0xFF00E676), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: isBuy ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      isBuy ? 'Beli Sekarang' : 'Jual Sekarang',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}