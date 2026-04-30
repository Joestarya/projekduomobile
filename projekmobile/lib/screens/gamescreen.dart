import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../service/api_config.dart';

// ─────────────────────────────────────────────
// ENUMS & MODELS
// ─────────────────────────────────────────────
enum GamePhase { idle, active, resolving, result }

enum Prediction { up, down }

class RoundResult {
  final Prediction prediction;
  final double entryPrice;
  final double exitPrice;
  final bool isCorrect;
  final int pointsEarned;
  final DateTime timestamp;

  const RoundResult({
    required this.prediction,
    required this.entryPrice,
    required this.exitPrice,
    required this.isCorrect,
    required this.pointsEarned,
    required this.timestamp,
  });

  double get priceDelta => exitPrice - entryPrice;
}

class _GameAsset {
  final String name;
  final String symbol;
  final String pair;
  final double price;

  const _GameAsset({
    required this.name,
    required this.symbol,
    required this.pair,
    required this.price,
  });
}

// ─────────────────────────────────────────────
// CANDLE CHART PAINTER
// ─────────────────────────────────────────────
class _CandleChartPainter extends CustomPainter {
  final List<Map<String, double>> candles;
  final double? entryPrice;

  const _CandleChartPainter({required this.candles, this.entryPrice});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final allHigh = candles.map((c) => c['high']!).reduce(max);
    final allLow = candles.map((c) => c['low']!).reduce(min);
    final priceRange = (allHigh - allLow).abs();
    if (priceRange == 0) return;

    const topPad = 4.0;
    const botPad = 4.0;
    final chartH = size.height - topPad - botPad;

    double toY(double price) =>
        topPad + chartH - ((price - allLow) / priceRange) * chartH;

    final candleW = (size.width / candles.length) * 0.55;
    final spacing = size.width / candles.length;

    if (entryPrice != null) {
      final ey = toY(entryPrice!);
      final dashPaint = Paint()
        ..color = const Color(0xFF3A5070)
        ..strokeWidth = 0.8;
      double dx = 0;
      while (dx < size.width) {
        canvas.drawLine(
          Offset(dx, ey),
          Offset(min(dx + 6, size.width), ey),
          dashPaint,
        );
        dx += 11;
      }
    }

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = i * spacing + spacing / 2;
      final isUp = c['close']! >= c['open']!;
      final bodyColor = isUp
          ? const Color(0xFF26A69A)
          : const Color(0xFFEF5350);

      canvas.drawLine(
        Offset(cx, toY(c['high']!)),
        Offset(cx, toY(c['low']!)),
        Paint()
          ..color = bodyColor.withOpacity(0.5)
          ..strokeWidth = 1,
      );

      final bTop = min(toY(c['open']!), toY(c['close']!));
      final bBot = max(toY(c['open']!), toY(c['close']!));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - candleW / 2, bTop, candleW, max(bBot - bTop, 1.0)),
          const Radius.circular(1),
        ),
        Paint()..color = bodyColor,
      );
    }
  }

  @override
  bool shouldRepaint(_CandleChartPainter o) =>
      o.candles != candles || o.entryPrice != entryPrice;
}

// ─────────────────────────────────────────────
// TIMER ARC PAINTER
// ─────────────────────────────────────────────
class _TimerArcPainter extends CustomPainter {
  final double progress;

  const _TimerArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 3;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF111827)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final Color arcColor;
    if (progress > 0.5) {
      arcColor = const Color(0xFF26A69A);
    } else if (progress > 0.25) {
      arcColor = Color.lerp(
        const Color(0xFFF59E0B),
        const Color(0xFF26A69A),
        (progress - 0.25) * 4,
      )!;
    } else {
      arcColor = Color.lerp(
        const Color(0xFFEF5350),
        const Color(0xFFF59E0B),
        progress * 4,
      )!;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TimerArcPainter o) => o.progress != progress;
}

// ─────────────────────────────────────────────
// GAME SCREEN
// ─────────────────────────────────────────────
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const int _roundSeconds = 60;

  GamePhase _phase = GamePhase.idle;
  Prediction? _prediction;
  String _selectedPair = '';
  double _currentPrice = 0;
  double _entryPrice = 0;
  double _secondsLeft = _roundSeconds.toDouble();

  // Skor sederhana
  int _totalScore = 0;

  RoundResult? _lastResult;
  List<Map<String, double>> _candles = [];
  List<_GameAsset> _availableAssets = [];
  bool _isLoadingAssets = true;

<<<<<<< HEAD
  // ── AI State ───────────────────────────────
  bool _isAiLoading = false;
  String? _aiPrediction;
  String? _aiReason;

  // ── Timers ─────────────────────────────────
=======
>>>>>>> 598a8293894848a27532c392fa5a04e5f23e0810
  Timer? _priceTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    _fetchAvailableAssets();
    _priceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _fetchPrice(),
    );
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── Data fetching — HANYA dari backend ───────
  Future<void> _fetchAvailableAssets() async {
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.endpoint('/crypto/prices')))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final List assets = (body['data'] as List?) ?? [];

      final parsed = assets
          .map<_GameAsset?>((a) {
            final name = a['name']?.toString() ?? '';
            final symbol = a['symbol']?.toString() ?? '';
            final pair = a['pair']?.toString() ?? '';
            final price = num.tryParse(a['price']?.toString() ?? '');

            if (name.isEmpty ||
                symbol.isEmpty ||
                pair.isEmpty ||
                price == null) {
              return null;
            }

            return _GameAsset(
              name: name,
              symbol: symbol,
              pair: pair,
              price: price.toDouble(),
            );
          })
          .whereType<_GameAsset>()
          .toList();

      if (!mounted) return;
      setState(() {
        _availableAssets = parsed;
        _isLoadingAssets = false;
        if (_selectedPair.isEmpty && parsed.isNotEmpty) {
          _selectedPair = parsed.first.pair;
          _fetchPrice();
          _fetchCandles();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAssets = false);
      }
    }
  }

  Future<void> _fetchPrice() async {
    if (_selectedPair.isEmpty) return;
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.endpoint('/crypto/prices')))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final List assets = (body['data'] as List?) ?? [];
      final match = assets.firstWhere(
        (a) => a['pair'] == _selectedPair,
        orElse: () => null,
      );
      if (match != null && mounted) {
        setState(() => _currentPrice = (match['price'] as num).toDouble());
      }
    } catch (_) {}
  }

  Future<void> _fetchCandles() async {
    if (_selectedPair.isEmpty) return;
    try {
      final url = ApiConfig.endpoint(
        '/crypto/klines?symbol=$_selectedPair&interval=1m&limit=32',
      );
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final List raw = body['data'] ?? [];
      final parsed = raw
          .map<Map<String, double>>((k) {
            if (k is Map) {
              return {
                'open': (k['open'] as num).toDouble(),
                'high': (k['high'] as num).toDouble(),
                'low': (k['low'] as num).toDouble(),
                'close': (k['close'] as num).toDouble(),
              };
            }
            return {};
          })
          .where((m) => m.isNotEmpty)
          .toList();
      if (mounted) setState(() => _candles = parsed);
    } catch (_) {}
  }

<<<<<<< HEAD
  // ─────────────────────────────────────────────
  // AI PREDICTION
  // ─────────────────────────────────────────────
  Future<void> _askAI() async {
    if (_candles.isEmpty || _isAiLoading) return;
    setState(() {
      _isAiLoading = true;
      _aiPrediction = null;
      _aiReason = null;
    });

    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.endpoint('/ai/predict')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'symbol': _selectedPair,
          'candles': _candles,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (mounted) {
          setState(() {
            _aiPrediction = body['prediction'];
            _aiReason = body['reason'];
            _isAiLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAiLoading = false;
            _aiReason = 'Gagal menghubungi AI Server.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _aiReason = 'Terjadi kesalahan jaringan saat bertanya ke AI.';
        });
      }
    }
  }

  // GAME LOGIC
=======
  // ── Game logic ───────────────────────────────
>>>>>>> 598a8293894848a27532c392fa5a04e5f23e0810
  void _startRound(Prediction pred) {
    if (_phase != GamePhase.idle || _currentPrice == 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _prediction = pred;
      _phase = GamePhase.active;
      _entryPrice = _currentPrice;
      _secondsLeft = _roundSeconds.toDouble();
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft -= 0.1);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _finalizeRound();
      }
    });
  }

  Future<void> _finalizeRound() async {
    setState(() => _phase = GamePhase.resolving);
    await _fetchPrice();
    await Future.delayed(const Duration(milliseconds: 200));

    final exitPrice = _currentPrice;
    final priceWentUp = exitPrice > _entryPrice;
    final correct =
        (_prediction == Prediction.up && priceWentUp) ||
        (_prediction == Prediction.down && !priceWentUp);

    final earned = correct ? 100 : 0;
    HapticFeedback.lightImpact();

    final result = RoundResult(
      prediction: _prediction!,
      entryPrice: _entryPrice,
      exitPrice: exitPrice,
      isCorrect: correct,
      pointsEarned: earned,
      timestamp: DateTime.now(),
    );

    setState(() {
      _phase = GamePhase.result;
      _lastResult = result;
      if (correct) _totalScore += earned;
    });

    await _fetchCandles();
  }

  void _resetRound() {
    setState(() {
      _phase = GamePhase.idle;
      _prediction = null;
      _lastResult = null;
      _secondsLeft = _roundSeconds.toDouble();
      _aiPrediction = null;
      _aiReason = null;
    });
  }

  void _selectPair(String pair) {
    if (_phase != GamePhase.idle) return;
    setState(() {
      _selectedPair = pair;
      _currentPrice = 0;
      _candles = [];
      _aiPrediction = null;
      _aiReason = null;
    });
    _fetchPrice();
    _fetchCandles();
  }

  // ── Format helpers ───────────────────────────
  String _fmtPrice(double v) {
    if (v == 0) return '—';
    if (v >= 10000) {
      return '\$${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    }
    if (v >= 1) return '\$${v.toStringAsFixed(2)}';
    return '\$${v.toStringAsFixed(4)}';
  }

  String _fmtDelta(double v, {int decimals = 2}) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(v.abs() < 1 ? 4 : decimals)}';
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeZone =
        'UTC${(now.timeZoneOffset.inHours > 0 ? '+' : '')}${now.timeZoneOffset.inHours}';

    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1018),
        elevation: 1,
        leading: Navigator.of(context).canPop()
            ? GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF3A5070),
                  size: 18,
                ),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Market Forecast',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Timezone: $timeZone',
              style: const TextStyle(color: Color(0xFF2A3A5A), fontSize: 9),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$_totalScore',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
                const Text(
                  'SCORE',
                  style: TextStyle(
                    color: Color(0xFF2A3A5A),
                    fontSize: 8,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    _buildAssetTabs(),
                    const SizedBox(height: 12),
                    _buildPriceTicker(),
                    const SizedBox(height: 12),
                    _buildChart(),
                    const SizedBox(height: 22),
                    if (_phase != GamePhase.idle) _buildGameSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _phase == GamePhase.idle
          ? _buildBottomGameMenu()
          : null,
    );
  }

  // ── Bottom Game Menu ─────────────────────────
  Widget _buildBottomGameMenu() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF0E1420), width: 1)),
        color: Color(0xFF080B12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR FORECAST',
            style: TextStyle(
              color: Color(0xFF2A3A5A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _forecastButton(Prediction.up)),
              const SizedBox(width: 10),
              Expanded(child: _forecastButton(Prediction.down)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Asset tabs ───────────────────────────────
  Widget _buildAssetTabs() {
    if (_isLoadingAssets) {
      return const Center(
        child: SizedBox(
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF1A2535),
          ),
        ),
      );
    }

    if (_availableAssets.isEmpty) {
      return const Center(
        child: Text(
          'No assets available',
          style: TextStyle(color: Color(0xFF3A5070), fontSize: 12),
        ),
      );
    }

    return Row(
      children: _availableAssets.asMap().entries.map((entry) {
        final i = entry.key;
        final asset = entry.value;
        final pair = asset.pair;
        final isSelected = pair == _selectedPair;
        final isDisabled = _phase != GamePhase.idle;
        final gradients = _gradientForSymbol(asset.symbol);
        final accentColor = gradients.first;

        return Expanded(
          child: GestureDetector(
            onTap: isDisabled ? null : () => _selectPair(pair),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(
                right: i < _availableAssets.length - 1 ? 6 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withOpacity(0.07)
                    : const Color(0xFF0C1018),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? accentColor.withOpacity(0.3)
                      : const Color(0xFF0E1420),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    asset.symbol,
                    style: TextStyle(
                      color: isSelected
                          ? accentColor
                          : isDisabled
                          ? const Color(0xFF1A2535)
                          : const Color(0xFF3A5070),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'USDT',
                    style: TextStyle(
                      color: isSelected
                          ? accentColor.withOpacity(0.4)
                          : const Color(0xFF151E2E),
                      fontSize: 9,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Price ticker ──────────────────────────────
  Widget _buildPriceTicker() {
    final asset = _availableAssets.firstWhere(
      (a) => a.pair == _selectedPair,
      orElse: () => _availableAssets.isNotEmpty
          ? _availableAssets.first
          : _GameAsset(name: '-', symbol: '-', pair: '-', price: 0),
    );
    final gradients = _gradientForSymbol(asset.symbol);
    final accentColor = gradients.first;
    final inRound = _phase == GamePhase.active;
    final delta = inRound ? _currentPrice - _entryPrice : 0.0;
    final isAhead = delta >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1018),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0E1420), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accentColor.withOpacity(0.15),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              asset.symbol,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                asset.name,
                style: const TextStyle(color: Color(0xFF3A5070), fontSize: 12),
              ),
              Text(
                '${asset.symbol}/USDT',
                style: const TextStyle(color: Color(0xFF1A2535), fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtPrice(_currentPrice),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
              if (inRound)
                Text(
                  '${isAhead ? "+" : ""}${_fmtDelta(delta)}',
                  style: TextStyle(
                    color: isAhead
                        ? const Color(0xFF26A69A)
                        : const Color(0xFFEF5350),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF26A69A),
                      ),
                    ),
                    const Text(
                      'Live',
                      style: TextStyle(color: Color(0xFF2A3A5A), fontSize: 10),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Chart ─────────────────────────────────────
  Widget _buildChart() {
    return Container(
      height: 130,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF080B12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0E1420), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '1-MIN CANDLES',
                style: TextStyle(
                  color: Color(0xFF1A2535),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _candles.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF1A2535),
                      ),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _CandleChartPainter(
                      candles: _candles,
                      entryPrice: _phase == GamePhase.active
                          ? _entryPrice
                          : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Game section routing ──────────────────────
  Widget _buildGameSection() {
    switch (_phase) {
      case GamePhase.idle:
        return const SizedBox.shrink();
      case GamePhase.active:
        return _buildActivePanel();
      case GamePhase.resolving:
        return _buildResolvingPanel();
      case GamePhase.result:
        return _buildResultPanel();
    }
  }
<<<<<<< HEAD
  // ── IDLE ──────────────────────────────────
  Widget _buildIdlePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR FORECAST',
          style: TextStyle(
            color: Color(0xFF2A3A5A),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Where will the price be in 60 seconds?',
          style: TextStyle(color: Color(0xFF3A5070), fontSize: 13),
        ),
        const SizedBox(height: 14),
        _buildAiPredictionPanel(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _forecastButton(Prediction.up)),
            const SizedBox(width: 10),
            Expanded(child: _forecastButton(Prediction.down)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.info_outline_rounded,
                size: 11, color: Color(0xFF1A2535)),
            SizedBox(width: 5),
            Text(
              '+100 pts base  ·  +20 pts per streak level',
              style: TextStyle(color: Color(0xFF1A2535), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
=======
>>>>>>> 598a8293894848a27532c392fa5a04e5f23e0810

  Widget _buildAiPredictionPanel() {
    if (_aiPrediction != null || _aiReason != null) {
      final isUp = _aiPrediction?.toLowerCase() == 'higher';
      final isDown = _aiPrediction?.toLowerCase() == 'lower';
      final accentColor = isUp ? const Color(0xFF26A69A) : (isDown ? const Color(0xFFEF5350) : const Color(0xFF9945FF));

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.05),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: accentColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'AI PREDICTION: ${_aiPrediction ?? "Unknown"}',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _aiReason ?? '',
              style: const TextStyle(color: Color(0xFF8EA8C0), fontSize: 11, height: 1.4),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _askAI,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF9945FF).withOpacity(0.3), width: 1),
        ),
        alignment: Alignment.center,
        child: _isAiLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9945FF)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.auto_awesome, color: Color(0xFF9945FF), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Ask AI for Forecast',
                    style: TextStyle(
                      color: Color(0xFF9945FF),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _forecastButton(Prediction pred) {
    final isUp = pred == Prediction.up;
    final color = isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return GestureDetector(
      onTap: () => _startRound(pred),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.18), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                isUp ? Icons.north_rounded : Icons.south_rounded,
                color: color,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUp ? 'Higher' : 'Lower',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  isUp ? 'Price goes up' : 'Price goes down',
                  style: const TextStyle(
                    color: Color(0xFF2A3A5A),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Active ────────────────────────────────────
  Widget _buildActivePanel() {
    final progress = _secondsLeft / _roundSeconds;
    final isUp = _prediction == Prediction.up;
    final predColor = isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final delta = _currentPrice - _entryPrice;
    final onTrack = (isUp && delta > 0) || (!isUp && delta < 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(60, 60),
                    painter: _TimerArcPainter(progress: progress),
                  ),
                  Text(
                    _secondsLeft.ceil().toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resolves in ${_secondsLeft.ceil()} seconds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: onTrack
                            ? const Color(0xFF26A69A)
                            : const Color(0xFFEF5350),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      onTrack ? 'Correct' : 'Off track',
                      style: TextStyle(
                        color: onTrack
                            ? const Color(0xFF26A69A)
                            : const Color(0xFFEF5350),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            _countdownTimer?.cancel();
            setState(() {
              _phase = GamePhase.idle;
              _prediction = null;
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2A3A5A),
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Cancel round', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── Resolving ─────────────────────────────────
  Widget _buildResolvingPanel() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF2A3A5A),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Fetching final price…',
            style: TextStyle(color: Color(0xFF2A3A5A), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Result ────────────────────────────────────
  Widget _buildResultPanel() {
    final r = _lastResult!;
    final correct = r.isCorrect;
    final accentColor = correct
        ? const Color(0xFF26A69A)
        : const Color(0xFFEF5350);
    final deltaPct = r.entryPrice == 0
        ? 0.0
        : ((r.exitPrice - r.entryPrice) / r.entryPrice) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accentColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                correct ? Icons.check_rounded : Icons.close_rounded,
                color: accentColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  correct ? 'Correct forecast' : 'Incorrect forecast',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  correct
                      ? 'Price moved as you predicted'
                      : 'Price moved in the opposite direction',
                  style: const TextStyle(
                    color: Color(0xFF2A3A5A),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1018),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0E1420), width: 1),
          ),
          child: Column(
            children: [
              _dataRow('Exit price', _fmtPrice(r.exitPrice), Colors.white),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: Color(0xFF0E1420), height: 1),
              ),
              _dataRow(
                'Price change',
                '${_fmtDelta(r.priceDelta)} (${deltaPct >= 0 ? "+" : ""}${deltaPct.toStringAsFixed(3)}%)',
                r.exitPrice >= r.entryPrice
                    ? const Color(0xFF26A69A)
                    : const Color(0xFFEF5350),
              ),
              if (correct) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF0E1420), height: 1),
                ),
                _dataRow(
                  'Points earned',
                  '+${r.pointsEarned}',
                  const Color(0xFF8EA8C0),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _resetRound,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1825),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1A2540), width: 1),
            ),
            alignment: Alignment.center,
            child: const Text(
              'New Round',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dataRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF2A3A5A), fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ── History ───────────────────────────────────
}
