import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import '../service/api_config.dart';
import 'gamescreen.dart';

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
// MAIN SCREEN
// ─────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _priceRefreshInterval = Duration(milliseconds: 2000);
  static const Duration _chartRefreshInterval = Duration(minutes: 5);

  // ── State ──────────────────────────────────
  bool _isPrivacyMode = false;
  double _totalBalance = 950.0;
  bool _isLoadingPrices = true;
  bool _isFetchingPrices = false;
  bool _hasPendingPriceFetch = false;
  String? _priceError;
  String? _lastUpdatedAt;
  List<_AssetItem> _assets = const [];

  // Sparkline data cache per symbol
  final Map<String, List<double>> _sparklineCache = {};

  // ── Timers & Subscriptions ─────────────────
  Timer? _priceRefreshTimer;
  Timer? _chartRefreshTimer;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  DateTime _lastShakeTime = DateTime.now();

  // ── Animation ─────────────────────────────

  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _startShakeDetection();
    _requestPriceFetch(showLoader: true);
    _fetchAllSparklines();

    _priceRefreshTimer = Timer.periodic(_priceRefreshInterval, (_) {
      _requestPriceFetch(showLoader: false);
    });
    _chartRefreshTimer = Timer.periodic(_chartRefreshInterval, (_) {
      _fetchAllSparklines();
    });
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
          'https://api.binance.com/api/v3/klines?symbol=$symbol&interval=1h&limit=24';
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
      }

      if (!mounted) return;
      setState(() {
        _assets = nextAssets;
        _lastUpdatedAt = updatedAt;
        _priceError = null;
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
    _priceRefreshTimer?.cancel();
    _chartRefreshTimer?.cancel();
    _accelerometerSubscription?.cancel();
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
      backgroundColor: const Color.fromRGBO(12, 15, 26, 1),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildPortfolioCard(),
            ),
            const SizedBox(height: 20),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildAssetsHeader(),
            ),
            const SizedBox(height: 8),
            // Divider
            Container(height: 1, color: const Color(0xFF1A2035)),
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
    return AppBar(
      backgroundColor: const Color(0xFF0C0F1A),
      elevation: 0,
      title: const Text(
        'Jaga Lilin',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      actions: [
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GameScreen()),
            );
          },
          icon: const Icon(
            Icons.sports_esports_rounded,
            color: Color(0xFF9D97FF),
            size: 22,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // PORTFOLIO CARD
  // ─────────────────────────────────────────────
  Widget _buildPortfolioCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1520),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3870), width: 1),
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
                  color: Color(0xFF7A90B0),
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
            _isPrivacyMode ? '•••••••••' : _formatUsd(_totalBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C853).withOpacity(0.25),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      color: Color(0xFF00E676),
                      size: 11,
                    ),
                    SizedBox(width: 3),
                    Text(
                      '\$15.30  (+1.6%)',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 12),
      
        ],
      ),
    );
  }

  Widget _buildQuickStat(String symbol, double? price) {
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
            price != null ? _formatUsd(price) : '-',
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
        Row(
          children: [
            if (!_isLoadingPrices && _priceError == null)
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00E676),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            if (_lastUpdatedAt != null) ...[
              const SizedBox(width: 10),
              Text(
                _formatUpdatedTime(_lastUpdatedAt!),
                style: const TextStyle(color: Color(0xFF3A5070), fontSize: 11),
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

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _assets.length,
      itemBuilder: (context, index) {
        return _buildAssetTile(_assets[index]);
      },
    );
  }

  // ─────────────────────────────────────────────
  // ASSET TILE — Mirip Stockbit dengan mini chart
  // ─────────────────────────────────────────────
  Widget _buildAssetTile(_AssetItem asset) {
    final isUp = asset.changePercent >= 0;

    // Warna harga berdasarkan flash atau % perubahan
    final priceColor = isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252);

    // Sparkline — gunakan dari cache atau data dummy
    final sparkData = _sparklineCache[asset.pair];
    final hasChart = sparkData != null && sparkData.length > 2;

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF131929), width: 1)),
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
                color: _gradientForSymbol(asset.symbol).first,
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
                    asset.name,
                    style: const TextStyle(
                      color: Color(0xFF4A6080),
                      fontSize: 12,
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
                  Text(
                    _formatUsd(asset.priceUsd),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: priceColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -0.3,
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
          ],
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
    final seed = symbol.codeUnits.fold(0, (sum, c) => sum + c);
    final rand = Random(seed);
    final hue = rand.nextInt(360).toDouble();
    final sat = 0.55 + rand.nextDouble() * 0.35;
    final light = 0.45 + rand.nextDouble() * 0.18;
    final base = HSLColor.fromAHSL(1, hue, sat, light).toColor();
    final altHue = (hue + 40 + rand.nextDouble() * 50) % 360;
    final alt = HSLColor.fromAHSL(
      1,
      altHue,
      min(1, sat + 0.08),
      min(1, light + 0.1),
    ).toColor();
    return [base, alt];
  }
}
