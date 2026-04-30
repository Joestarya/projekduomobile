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
  double get priceDeltaPct =>
      entryPrice == 0 ? 0 : (priceDelta / entryPrice) * 100;
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

    // Entry price dashed line
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
      final bodyColor =
          isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

      // Wick
      canvas.drawLine(
        Offset(cx, toY(c['high']!)),
        Offset(cx, toY(c['low']!)),
        Paint()
          ..color = bodyColor.withOpacity(0.5)
          ..strokeWidth = 1,
      );

      // Body
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
  final double progress; // 1.0 → 0.0 as time runs out

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

    // Color shifts: teal (full) → amber (mid) → red (low)
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
// ASSET CONFIG
const List<Map<String, String>> _assets = [
  {'pair': 'BTCUSDT', 'ticker': 'BTC', 'name': 'Bitcoin'},
  {'pair': 'ETHUSDT', 'ticker': 'ETH', 'name': 'Ethereum'},
  {'pair': 'BNBUSDT', 'ticker': 'BNB', 'name': 'BNB'},
  {'pair': 'SOLUSDT', 'ticker': 'SOL', 'name': 'Solana'},
];

const Map<String, Color> _assetColors = {
  'BTCUSDT': Color(0xFFF7931A),
  'ETHUSDT': Color(0xFF627EEA),
  'BNBUSDT': Color(0xFFF0B90B),
  'SOLUSDT': Color(0xFF9945FF),
};

// MAIN SCREEN
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const int _roundSeconds = 60;

  // ── Game state ─────────────────────────────
  GamePhase _phase = GamePhase.idle;
  Prediction? _prediction;
  String _selectedPair = 'BTCUSDT';
  double _currentPrice = 0;
  double _entryPrice = 0;
  double _secondsLeft = _roundSeconds.toDouble();

  // ── Stats ──────────────────────────────────
  int _totalScore = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _totalRounds = 0;
  int _wins = 0;

  // ── Data ───────────────────────────────────
  RoundResult? _lastResult;
  List<Map<String, double>> _candles = [];
  final List<RoundResult> _history = [];

  // ── AI State ───────────────────────────────
  bool _isAiLoading = false;
  String? _aiPrediction;
  String? _aiReason;

  // ── Timers ─────────────────────────────────
  Timer? _priceTimer;
  Timer? _countdownTimer;

  // ── Animations (minimal) ───────────────────
  late AnimationController _screenFadeController;
  late AnimationController _resultFadeController;
  late Animation<double> _screenFade;
  late Animation<double> _resultFade;

  @override
  void initState() {
    super.initState();

    _screenFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _screenFade =
        CurvedAnimation(parent: _screenFadeController, curve: Curves.easeOut);

    _resultFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _resultFade =
        CurvedAnimation(parent: _resultFadeController, curve: Curves.easeOut);

    _fetchPrice();
    _fetchCandles();
    _priceTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _fetchPrice());

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _screenFadeController.forward());
  }

  @override
  void dispose() {
    _screenFadeController.dispose();
    _resultFadeController.dispose();
    _priceTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // DATA FETCHING
  // ─────────────────────────────────────────────
  Future<void> _fetchPrice() async {
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
    final urls = [
      ApiConfig.endpoint(
          '/crypto/klines?symbol=$_selectedPair&interval=1m&limit=32'),
      'https://api.binance.com/api/v3/klines?symbol=$_selectedPair&interval=1m&limit=32',
    ];
    for (final url in urls) {
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        final body = jsonDecode(resp.body);
        final List raw = body is Map ? (body['data'] ?? []) : body;
        final parsed = raw.map<Map<String, double>>((k) {
          if (k is Map) {
            return {
              'open': (k['open'] as num).toDouble(),
              'high': (k['high'] as num).toDouble(),
              'low': (k['low'] as num).toDouble(),
              'close': (k['close'] as num).toDouble(),
            };
          }
          return {
            'open': double.parse(k[1].toString()),
            'high': double.parse(k[2].toString()),
            'low': double.parse(k[3].toString()),
            'close': double.parse(k[4].toString()),
          };
        }).toList();
        if (mounted) setState(() => _candles = parsed);
        return;
      } catch (_) {}
    }
  }

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
    _countdownTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
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
    final correct = (_prediction == Prediction.up && priceWentUp) ||
        (_prediction == Prediction.down && !priceWentUp);

    final earned = correct ? 100 + (_streak * 20) : 0;

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
      _totalRounds++;
      if (correct) {
        _wins++;
        _streak++;
        _bestStreak = max(_bestStreak, _streak);
        _totalScore += earned;
      } else {
        _streak = 0;
      }
      _history.insert(0, result);
      if (_history.length > 20) _history.removeLast();
    });

    _resultFadeController.forward(from: 0);
    await _fetchCandles();
  }

  void _resetRound() {
    _resultFadeController.reset();
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

  // ─────────────────────────────────────────────
  // FORMATTING
  // ─────────────────────────────────────────────
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

  double get _accuracy =>
      _totalRounds == 0 ? 0 : (_wins / _totalRounds * 100);

  // BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: FadeTransition(
        opacity: _screenFade,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              _buildStatsBar(),
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
                      _buildGameSection(),
                      const SizedBox(height: 28),
                      if (_history.isNotEmpty) _buildHistory(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
  // HEADER
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: Color(0xFF0E1420), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF3A5070),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Market Forecast',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Practice reading price direction',
                  style: TextStyle(color: Color(0xFF2A3A5A), fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_totalScore',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'SCORE',
                style: TextStyle(
                  color: Color(0xFF2A3A5A),
                  fontSize: 9,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // STATS BAR
  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: Color(0xFF0A0D15), width: 1)),
      ),
      child: Row(
        children: [
          _statCell('Accuracy', '${_accuracy.toStringAsFixed(0)}%'),
          _statDivider(),
          _statCell(
            'Streak',
            '$_streak',
            valueColor: _streak >= 3
                ? const Color(0xFF26A69A)
                : Colors.white,
          ),
          _statDivider(),
          _statCell('Best', '$_bestStreak'),
          _statDivider(),
          _statCell('Rounds', '$_totalRounds'),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value,
      {Color valueColor = Colors.white}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              )),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF2A3A5A), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: const Color(0xFF0E1420),
      );

  // ASSET TABS
  Widget _buildAssetTabs() {
    return Row(
      children: _assets.asMap().entries.map((entry) {
        final i = entry.key;
        final a = entry.value;
        final pair = a['pair']!;
        final isSelected = pair == _selectedPair;
        final isDisabled = _phase != GamePhase.idle;
        final accentColor = _assetColors[pair]!;

        return Expanded(
          child: GestureDetector(
            onTap: isDisabled ? null : () => _selectPair(pair),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(right: i < _assets.length - 1 ? 6 : 0),
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
                    a['ticker']!,
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
  // PRICE TICKER
  Widget _buildPriceTicker() {
    final meta = _assets.firstWhere((a) => a['pair'] == _selectedPair);
    final accentColor = _assetColors[_selectedPair]!;
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
              border: Border.all(color: accentColor.withOpacity(0.15), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              meta['ticker']!,
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
              Text(meta['name']!,
                  style: const TextStyle(
                      color: Color(0xFF3A5070), fontSize: 12)),
              Text(
                '${meta['ticker']!}/USDT',
                style: const TextStyle(
                    color: Color(0xFF1A2535), fontSize: 10),
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
                  '${isAhead ? "+" : ""}${_fmtDelta(delta)} vs entry',
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
                      style: TextStyle(
                          color: Color(0xFF2A3A5A), fontSize: 10),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
  // CHART
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
              if (_phase == GamePhase.active) ...[
                const Spacer(),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF3A5070),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Entry line',
                  style: TextStyle(color: Color(0xFF1A2535), fontSize: 9),
                ),
              ],
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
  // GAME SECTION (routing)
  Widget _buildGameSection() {
    switch (_phase) {
      case GamePhase.idle:
        return _buildIdlePanel();
      case GamePhase.active:
        return _buildActivePanel();
      case GamePhase.resolving:
        return _buildResolvingPanel();
      case GamePhase.result:
        return _buildResultPanel();
    }
  }
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
    final color =
        isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

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
                      color: Color(0xFF2A3A5A), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  // ── ACTIVE ─────────────────────────────────
  Widget _buildActivePanel() {
    final progress = _secondsLeft / _roundSeconds;
    final isUp = _prediction == Prediction.up;
    final predColor =
        isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final delta = _currentPrice - _entryPrice;
    final onTrack = (isUp && delta > 0) || (!isUp && delta < 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Forecast label
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: predColor.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: predColor.withOpacity(0.12), width: 1),
          ),
          child: Row(
            children: [
              Icon(
                isUp ? Icons.north_rounded : Icons.south_rounded,
                color: predColor,
                size: 14,
              ),
              const SizedBox(width: 7),
              Text(
                'Forecast: ${isUp ? "Higher" : "Lower"}',
                style: TextStyle(
                  color: predColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                'Entry  ${_fmtPrice(_entryPrice)}',
                style: const TextStyle(
                    color: Color(0xFF2A3A5A), fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Timer row
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
                      onTrack
                          ? 'Correct'
                          : 'Off track',
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
          child: const Text('Cancel round',
              style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
  // ── RESOLVING ──────────────────────────────
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
  // ── RESULT ─────────────────────────────────
  Widget _buildResultPanel() {
    final r = _lastResult!;
    final correct = r.isCorrect;
    final accentColor =
        correct ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final deltaPct = r.entryPrice == 0
        ? 0.0
        : ((r.exitPrice - r.entryPrice) / r.entryPrice) * 100;

    return FadeTransition(
      opacity: _resultFade,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outcome row
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: accentColor.withOpacity(0.2), width: 1),
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
                    correct
                        ? 'Correct forecast'
                        : 'Incorrect forecast',
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
                        color: Color(0xFF2A3A5A), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Data table
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1018),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF0E1420), width: 1),
            ),
            child: Column(
              children: [
                _dataRow('Entry price', _fmtPrice(r.entryPrice),
                    Colors.white),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF0E1420), height: 1),
                ),
                _dataRow('Exit price', _fmtPrice(r.exitPrice),
                    Colors.white),
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
                    _streak > 1
                        ? 'Points  (×$_streak streak)'
                        : 'Points earned',
                    '+${r.pointsEarned}',
                    const Color(0xFF8EA8C0),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // New round button
          GestureDetector(
            onTap: _resetRound,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1825),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF1A2540), width: 1),
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
      ),
    );
  }

  Widget _dataRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF2A3A5A), fontSize: 12)),
        Text(value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            )),
      ],
    );
  }

  // HISTORY
  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ROUND HISTORY',
              style: TextStyle(
                color: Color(0xFF2A3A5A),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '$_wins of $_totalRounds correct',
              style: const TextStyle(
                  color: Color(0xFF1A2535), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Outcome trail (last 10)
        Row(
          children: _history.take(10).toList().reversed.map((r) {
            final c = r.isCorrect
                ? const Color(0xFF26A69A)
                : const Color(0xFFEF5350);
            return Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: c.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.withOpacity(0.2), width: 1),
              ),
              child: Icon(
                r.isCorrect ? Icons.north_rounded : Icons.south_rounded,
                color: c,
                size: 10,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),

        // Recent 5 rows
        ..._history.take(5).map((r) {
          final correct = r.isCorrect;
          final lineColor = correct
              ? const Color(0xFF26A69A)
              : const Color(0xFFEF5350);
          final delta = r.exitPrice - r.entryPrice;

          return Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1018),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF0A0D15), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: lineColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_fmtPrice(r.entryPrice)}  →  ${_fmtPrice(r.exitPrice)}',
                        style: const TextStyle(
                            color: Color(0xFF3A5070), fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${r.prediction == Prediction.up ? "Higher" : "Lower"} · '
                        'Actual ${delta >= 0 ? "+" : ""}${_fmtDelta(delta)}',
                        style: const TextStyle(
                            color: Color(0xFF1A2535), fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Text(
                  correct ? '+${r.pointsEarned}' : '—',
                  style: TextStyle(
                    color: correct
                        ? const Color(0xFF4A6080)
                        : const Color(0xFF1A2535),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}