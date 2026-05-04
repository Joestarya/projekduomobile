import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import '../../../service/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'price_alert/price_alert_screen.dart';
import '../../../../models/asset_item.dart';
import 'portfolio_card.dart';
import 'asset_tile.dart';

// ─────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────

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
  String _currencyMode = 'IDR';
  double _totalBalance = 0.0;
  Map<String, double> _userBalances = {};
  bool _isPortfolioConnected = false;
  bool _isLoadingPrices = true;
  bool _isFetchingPrices = false;
  bool _hasPendingPriceFetch = false;
  String? _priceError;
  String? _lastUpdatedAt;
  List<AssetItem> _assets = const [];
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
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

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

  double _getEurRate() {
    final eurAsset = _assets.where((a) => a.symbol == 'EUR').firstOrNull;
    if (eurAsset != null && eurAsset.priceUsd > 0) {
      return 1 / eurAsset.priceUsd;
    }
    return 0.92;
  }

  void _calculateTotalBalance() {
    double total = 0.0;
    for (var entry in _userBalances.entries) {
      final asset = entry.key;
      final amount = entry.value;

      if (asset == 'USDT' ||
          asset == 'USDC' ||
          asset == 'FDUSD' ||
          asset == 'BUSD') {
        total += amount;
      } else if (asset == 'IDR' || asset == 'BIDR' || asset == 'IDRT') {
        total += amount / _getIdrRate();
      } else if (asset == 'EUR') {
        total += amount / _getEurRate();
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

      final nextAssets = <AssetItem>[];
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

        final item = AssetItem(
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

  String _formatEur(double value) {
    if (value >= 10000) {
      final fixed = value.toStringAsFixed(0);
      return '€${fixed.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    } else if (value >= 1) {
      return '€${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    } else {
      return '€${value.toStringAsFixed(4)}';
    }
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
                  child: PortfolioCard(
                    isPrivacyMode: _isPrivacyMode,
                    isPortfolioConnected: _isPortfolioConnected,
                    currencyMode: _currencyMode,
                    totalBalance: _totalBalance,
                    idrRate: _getIdrRate(),
                    eurRate: _getEurRate(),
                    userBalances: _userBalances,
                    assets: _assets,
                    onTogglePrivacy: () =>
                        setState(() => _isPrivacyMode = !_isPrivacyMode),
                    formatIdr: _formatIdr,
                    formatUsd: _formatUsd,
                    formatEur: _formatEur,
                  ),
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
      preferredSize: const Size.fromHeight(60),
      child: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: const Text(
          'Jaga Lilin',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          _buildClockWidget(isCompact: isCompact),
          IconButton(
            icon: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PriceAlertScreen(
                  livePrices: {for (final a in _assets) a.symbol: a.priceUsd},
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClockWidget({required bool isCompact}) {
    return GestureDetector(
      onTap: _showTimezoneBottomSheet,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$_clockDisplay ${_selectedTimezone.label}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
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
              if (_currencyMode == 'USD') {
                _currencyMode = 'IDR';
              } else if (_currencyMode == 'IDR') {
                _currencyMode = 'EUR';
              } else {
                _currencyMode = 'USD';
              }
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

    final displayAssets = _assets.where((a) => a.symbol != 'USDT_IDR' && a.symbol != 'EUR').toList();
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
          child: AssetTile(
            asset: displayAssets[index],
            flashColor: _flashColors[displayAssets[index].symbol],
            sparkData: _sparklineCache[displayAssets[index].pair],
            userBalance: _userBalances[displayAssets[index].symbol] ?? 0.0,
            priceDisplay: _currencyMode == 'IDR'
                ? _formatIdr(displayAssets[index].priceUsd * _getIdrRate())
                : (_currencyMode == 'EUR'
                    ? _formatEur(displayAssets[index].priceUsd * _getEurRate())
                    : _formatUsd(displayAssets[index].priceUsd)),
            changePercentDisplay: _formatChangePercent(
              displayAssets[index].changePercent,
            ),
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
                  child: _OrderBottomSheet(
                    asset: displayAssets[index],
                    userBalance:
                        _userBalances[displayAssets[index].symbol] ?? 0.0,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// ORDER BOTTOM SHEET
// ─────────────────────────────────────────────
class _OrderBottomSheet extends StatefulWidget {
  final AssetItem asset;
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

  String _normalizeQuantity(String rawInput) {
    final normalized = rawInput.replaceAll(',', '.').trim();
    final parsed = double.tryParse(normalized);
    if (parsed == null) return normalized;
    if (normalized.contains('e') || normalized.contains('E')) {
      final fixed = parsed.toStringAsFixed(12);
      return fixed
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
    }
    return normalized;
  }

  String _formatAssetBalance(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(4);
    final fixed = value.toStringAsFixed(8);
    return fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _submitOrder() async {
    final amountText = _amountController.text.replaceAll(',', '.').trim();
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
        body['quoteOrderQty'] = _normalizeQuantity(amountText);
      } else {
        body['quantity'] = _normalizeQuantity(amountText);
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
          _errorMessage =
              respData['detail'] ??
              respData['message'] ??
              'Terjadi kesalahan tidak dikenal.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Error Jaringan. Pastikan Anda terkoneksi ke Internet dan tidak diblokir ISP.';
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
                'Saldo: ${_formatAssetBalance(widget.userBalance)} ${widget.asset.symbol}',
                style: const TextStyle(color: Color(0xFF8B9BB4), fontSize: 12),
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
                      color: isBuy
                          ? const Color(0xFF00E676)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isBuy
                            ? Colors.transparent
                            : const Color(0xFF3A5070),
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
                      color: !isBuy
                          ? const Color(0xFFFF5252)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !isBuy
                            ? Colors.transparent
                            : const Color(0xFF3A5070),
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
              labelText: isBuy
                  ? 'Jumlah USDT'
                  : 'Jumlah ${widget.asset.symbol}',
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
                border: Border.all(
                  color: const Color(0xFFFF5252).withOpacity(0.5),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFFF5252),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFF5252),
                        fontSize: 13,
                      ),
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
                border: Border.all(
                  color: const Color(0xFF00E676).withOpacity(0.5),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF00E676),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 13,
                      ),
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
                backgroundColor: isBuy
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFF5252),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
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
