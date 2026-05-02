import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/api_config.dart';
import '../../widgets/ai_prediction_card.dart';

// ─────────────────────────────────────────────
// APP THEME
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

  // Semantic colors (tidak diubah agar chart tetap terbaca)
  static const bullish = Color(0xFF26A69A);
  static const bearish = Color(0xFFEF5350);
  static const warning = Color(0xFFF59E0B);
}

// ─────────────────────────────────────────────
// ENUMS & MODELS
// ─────────────────────────────────────────────
enum GamePhase { idle, active, resolving, result }

enum Prediction { up, down }

// ── Timeframe config ──────────────────────────
class _TF {
  final String label;
  final String interval;
  final int durationSec;
  final int candleLimit;

  const _TF(this.label, this.interval, this.durationSec, this.candleLimit);
}

const List<_TF> _timeframes = [
  _TF('1m',  '1m',  60,   32),
  _TF('5m',  '5m',  300,  24),
  _TF('15m', '15m', 900,  20),
];

// ── Round result ──────────────────────────────
class RoundResult {
  final Prediction prediction;
  final double entryPrice;
  final double exitPrice;
  final bool isCorrect;
  final int pointsEarned;
  final int pointsLost;
  final DateTime timestamp;

  const RoundResult({
    required this.prediction,
    required this.entryPrice,
    required this.exitPrice,
    required this.isCorrect,
    required this.pointsEarned,
    required this.pointsLost,
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

    final allHigh    = candles.map((c) => c['high']!).reduce(max);
    final allLow     = candles.map((c) => c['low']!).reduce(min);
    final priceRange = (allHigh - allLow).abs();
    if (priceRange == 0) return;

    const topPad = 4.0;
    const botPad = 4.0;
    final chartH = size.height - topPad - botPad;

    double toY(double price) =>
        topPad + chartH - ((price - allLow) / priceRange) * chartH;

    final candleW = (size.width / candles.length) * 0.55;
    final spacing = size.width / candles.length;

    // Entry price dashed line — pakai accent agar terlihat di bg gelap
    if (entryPrice != null) {
      final ey = toY(entryPrice!);
      final dashPaint = Paint()
        ..color = AppTheme.accent.withOpacity(0.55)
        ..strokeWidth = 0.9;
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
      final c       = candles[i];
      final cx      = i * spacing + spacing / 2;
      final isUp    = c['close']! >= c['open']!;
      final bodyCol = isUp ? AppTheme.bullish : AppTheme.bearish;

      canvas.drawLine(
        Offset(cx, toY(c['high']!)),
        Offset(cx, toY(c['low']!)),
        Paint()
          ..color = bodyCol.withOpacity(0.5)
          ..strokeWidth = 1,
      );

      final bTop = min(toY(c['open']!), toY(c['close']!));
      final bBot = max(toY(c['open']!), toY(c['close']!));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - candleW / 2, bTop, candleW, max(bBot - bTop, 1.0)),
          const Radius.circular(1),
        ),
        Paint()..color = bodyCol,
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

    // Track ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppTheme.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Arc color: hijau → kuning → merah seiring progress turun
    final Color arcColor;
    if (progress > 0.5) {
      arcColor = AppTheme.bullish;
    } else if (progress > 0.25) {
      arcColor = Color.lerp(AppTheme.warning, AppTheme.bullish, (progress - 0.25) * 4)!;
    } else {
      arcColor = Color.lerp(AppTheme.bearish, AppTheme.warning, progress * 4)!;
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
// ASSET CONFIG
// ─────────────────────────────────────────────
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

// ─────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  // ── Timeframe ──────────────────────────────
  int _tfIndex = 0;
  _TF get _tf => _timeframes[_tfIndex];

  // ── Game state ─────────────────────────────
  GamePhase _phase = GamePhase.idle;
  Prediction? _prediction;
  String _selectedPair = 'BTCUSDT';
  double _currentPrice = 0;
  double _entryPrice = 0;
  double _secondsLeft = 0;

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

  // ── Timers ─────────────────────────────────
  Timer? _priceTimer;
  Timer? _countdownTimer;

  // ── Score sync ─────────────────────────────
  bool _scoreLoaded = false;
  String? _authToken;

  // ── Animations ─────────────────────────────
  late AnimationController _screenFadeController;
  late AnimationController _resultFadeController;
  late Animation<double> _screenFade;
  late Animation<double> _resultFade;

  // ─────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _secondsLeft = _tf.durationSec.toDouble();

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

    _loadScore();
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
  // SCORE PERSISTENCE
  // ─────────────────────────────────────────────
  Future<String?> _getToken() async {
    if (_authToken != null) return _authToken;
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('token');
    return _authToken;
  }

  Future<void> _loadScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _totalScore  = prefs.getInt('game_total_score')  ?? 0;
      _totalRounds = prefs.getInt('game_total_rounds') ?? 0;
      _wins        = prefs.getInt('game_total_wins')   ?? 0;
      _bestStreak  = prefs.getInt('game_best_streak')  ?? 0;
    });

    try {
      final token = await _getToken();
      if (token == null) return;

      final resp = await http
          .get(
            Uri.parse(ApiConfig.endpoint('/game/score')),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data        = jsonDecode(resp.body) as Map<String, dynamic>;
        final serverScore  = (data['total_score']  as num?)?.toInt() ?? 0;
        final serverRounds = (data['total_rounds'] as num?)?.toInt() ?? 0;
        final serverWins   = (data['total_wins']   as num?)?.toInt() ?? 0;
        final serverBest   = (data['best_streak']  as num?)?.toInt() ?? 0;

        if (mounted) {
          setState(() {
            _totalScore  = max(_totalScore,  serverScore);
            _totalRounds = max(_totalRounds, serverRounds);
            _wins        = max(_wins,        serverWins);
            _bestStreak  = max(_bestStreak,  serverBest);
          });
        }
        await _saveScoreLocal();
      }
    } catch (_) {}

    _scoreLoaded = true;
  }

  Future<void> _saveScoreLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game_total_score',  _totalScore);
    await prefs.setInt('game_total_rounds', _totalRounds);
    await prefs.setInt('game_total_wins',   _wins);
    await prefs.setInt('game_best_streak',  _bestStreak);
  }

  Future<void> _syncScoreToServer() async {
    try {
      final token = await _getToken();
      if (token == null) return;

      await http
          .post(
            Uri.parse(ApiConfig.endpoint('/game/score')),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'total_score':  _totalScore,
              'total_rounds': _totalRounds,
              'total_wins':   _wins,
              'best_streak':  _bestStreak,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
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
      final body  = jsonDecode(resp.body) as Map<String, dynamic>;
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
          '/crypto/klines?symbol=$_selectedPair&interval=${_tf.interval}&limit=${_tf.candleLimit}'),
      'https://api.binance.com/api/v3/klines?symbol=$_selectedPair&interval=${_tf.interval}&limit=${_tf.candleLimit}',
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
              'open':  (k['open']  as num).toDouble(),
              'high':  (k['high']  as num).toDouble(),
              'low':   (k['low']   as num).toDouble(),
              'close': (k['close'] as num).toDouble(),
            };
          }
          return {
            'open':  double.parse(k[1].toString()),
            'high':  double.parse(k[2].toString()),
            'low':   double.parse(k[3].toString()),
            'close': double.parse(k[4].toString()),
          };
        }).toList();
        if (mounted) setState(() => _candles = parsed);
        return;
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────
  // GAME LOGIC
  // ─────────────────────────────────────────────
  void _startRound(Prediction pred) {
    if (_phase != GamePhase.idle || _currentPrice == 0) return;
    HapticFeedback.selectionClick();

    setState(() {
      _prediction  = pred;
      _phase       = GamePhase.active;
      _entryPrice  = _currentPrice;
      _secondsLeft = _tf.durationSec.toDouble();
    });

    _countdownTimer?.cancel();
    _countdownTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) { timer.cancel(); return; }
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

    final exitPrice   = _currentPrice;
    final priceWentUp = exitPrice > _entryPrice;
    final correct = (_prediction == Prediction.up  &&  priceWentUp) ||
                    (_prediction == Prediction.down && !priceWentUp);
    final earned  = correct ? 100 + (_streak * 20) : 0;
    final losed   = !correct ? 100 : 0;

    HapticFeedback.lightImpact();

    final result = RoundResult(
      prediction:   _prediction!,
      entryPrice:   _entryPrice,
      exitPrice:    exitPrice,
      isCorrect:    correct,
      pointsEarned: earned,
      pointsLost:   losed,
      timestamp:    DateTime.now(),
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
        _totalScore = max(0, _totalScore - losed);
        _streak = 0;
      }
      _history.insert(0, result);
      if (_history.length > 20) _history.removeLast();
    });

    await _saveScoreLocal();
    _syncScoreToServer();

    _resultFadeController.forward(from: 0);
    await _fetchCandles();
  }

  void _resetRound() {
    _resultFadeController.reset();
    setState(() {
      _phase       = GamePhase.idle;
      _prediction  = null;
      _lastResult  = null;
      _secondsLeft = _tf.durationSec.toDouble();
    });
  }

  void _selectPair(String pair) {
    if (_phase != GamePhase.idle) return;
    setState(() {
      _selectedPair = pair;
      _currentPrice = 0;
      _candles      = [];
    });
    _fetchPrice();
    _fetchCandles();
  }

  void _selectTimeframe(int index) {
    if (_phase != GamePhase.idle) return;
    setState(() {
      _tfIndex     = index;
      _secondsLeft = _timeframes[index].durationSec.toDouble();
      _candles     = [];
    });
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

  String _fmtCountdown(double sec) {
    final s = sec.ceil();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  double get _accuracy =>
      _totalRounds == 0 ? 0 : (_wins / _totalRounds * 100);

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _screenFade,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),
                      _buildAssetTabs(),
                      const SizedBox(height: 10),
                      _buildTimeframeTabs(),
                      const SizedBox(height: 12),
                      _buildPriceTicker(),
                      const SizedBox(height: 12),
                      _buildChart(),
                      const SizedBox(height: 22),
                      _buildGameSection(),
                      const SizedBox(height: 28),
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

  // ─────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Market Forecast',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Practice reading price direction',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 11),
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
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'SCORE',
                style: TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 9,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TIMEFRAME TABS
  // ─────────────────────────────────────────────
  Widget _buildTimeframeTabs() {
    final isDisabled = _phase != GamePhase.idle;
    return Row(
      children: [
        const Text(
          'TIMEFRAME',
          style: TextStyle(
            color: AppTheme.textDim,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 10),
        ...List.generate(_timeframes.length, (i) {
          final tf         = _timeframes[i];
          final isSelected = i == _tfIndex;
          return GestureDetector(
            onTap: isDisabled ? null : () => _selectTimeframe(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accent.withOpacity(0.15)
                    : AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.accent.withOpacity(0.5)
                      : AppTheme.border,
                  width: 1,
                ),
              ),
              child: Text(
                tf.label,
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.accent
                      : isDisabled
                          ? AppTheme.textDim
                          : AppTheme.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }),
        if (isDisabled) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: const Text(
              'Locked during round',
              style: TextStyle(color: AppTheme.textDim, fontSize: 9),
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  // ASSET TABS
  // ─────────────────────────────────────────────
  Widget _buildAssetTabs() {
    return Row(
      children: _assets.asMap().entries.map((entry) {
        final i          = entry.key;
        final a          = entry.value;
        final pair       = a['pair']!;
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
                    ? accentColor.withOpacity(0.1)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? accentColor.withOpacity(0.4)
                      : AppTheme.border,
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
                              ? AppTheme.textDim
                              : AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'USDT',
                    style: TextStyle(
                      color: isSelected
                          ? accentColor.withOpacity(0.45)
                          : AppTheme.textDim,
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

  // ─────────────────────────────────────────────
  // PRICE TICKER
  // ─────────────────────────────────────────────
  Widget _buildPriceTicker() {
    final meta        = _assets.firstWhere((a) => a['pair'] == _selectedPair);
    final accentColor = _assetColors[_selectedPair]!;
    final inRound     = _phase == GamePhase.active;
    final delta       = inRound ? _currentPrice - _entryPrice : 0.0;
    final isAhead     = delta >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withOpacity(0.25), width: 1),
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
              Text(
                meta['name']!,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              Text(
                '${meta['ticker']!}/USDT · ${_tf.label}',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
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
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
              if (inRound)
                Text(
                  '${isAhead ? "+" : ""}${_fmtDelta(delta)} vs entry',
                  style: TextStyle(
                    color: isAhead ? AppTheme.bullish : AppTheme.bearish,
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
                        color: AppTheme.bullish,
                      ),
                    ),
                    const Text(
                      'Live',
                      style: TextStyle(color: AppTheme.textDim, fontSize: 10),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CHART
  // ─────────────────────────────────────────────
  Widget _buildChart() {
    return Container(
      height: 130,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_tf.label.toUpperCase()} CANDLES',
                style: const TextStyle(
                  color: AppTheme.textDim,
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
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Entry line',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 9),
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
                        color: AppTheme.textDim,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _CandleChartPainter(
                      candles: _candles,
                      entryPrice:
                          _phase == GamePhase.active ? _entryPrice : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // GAME SECTION (routing)
  // ─────────────────────────────────────────────
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

  // ── IDLE ──────────────────────────────────────
  Widget _buildIdlePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AiPredictionCard(selectedPair: _selectedPair, timeframe: _tf.interval),
        const SizedBox(height: 6),
        Text(
          'Where will the price be in ${_tf.label}?',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
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
            Icon(Icons.info_outline_rounded, size: 11, color: AppTheme.textDim),
            SizedBox(width: 5),
            Text(
              '+100 pts base  ·  +20 pts per streak level',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _forecastButton(Prediction pred) {
    final isUp  = pred == Prediction.up;
    final color = isUp ? AppTheme.bullish : AppTheme.bearish;

    return GestureDetector(
      onTap: () => _startRound(pred),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
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
                    color: AppTheme.textDim,
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

  // ── ACTIVE ───────────────────────────────────
  Widget _buildActivePanel() {
    final progress = _secondsLeft / _tf.durationSec;
    final isUp     = _prediction == Prediction.up;
    final delta    = _currentPrice - _entryPrice;
    final onTrack  = (isUp && delta > 0) || (!isUp && delta < 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Row(
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
                      _tf.durationSec > 60
                          ? _fmtCountdown(_secondsLeft)
                          : _secondsLeft.ceil().toString(),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: _tf.durationSec > 60 ? 11 : 17,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resolves in ${_fmtCountdown(_secondsLeft)}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
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
                            color: onTrack ? AppTheme.bullish : AppTheme.bearish,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          onTrack ? 'On track' : 'Off track',
                          style: TextStyle(
                            color: onTrack ? AppTheme.bullish : AppTheme.bearish,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Timeframe: ${_tf.label}',
                      style: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            _countdownTimer?.cancel();
            setState(() {
              _phase       = GamePhase.idle;
              _prediction  = null;
              _secondsLeft = _tf.durationSec.toDouble();
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.textDim,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Cancel round', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── RESOLVING ────────────────────────────────
  Widget _buildResolvingPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Fetching final price…',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── RESULT ───────────────────────────────────
  Widget _buildResultPanel() {
    final r           = _lastResult!;
    final correct     = r.isCorrect;
    final accentColor = correct ? AppTheme.bullish : AppTheme.bearish;
    final deltaPct    = r.entryPrice == 0
        ? 0.0
        : ((r.exitPrice - r.entryPrice) / r.entryPrice) * 100;

    return FadeTransition(
      opacity: _resultFade,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Result header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accentColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withOpacity(0.25),
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
                        color: AppTheme.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Data breakdown
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: Column(
              children: [
                _dataRow('Entry price', _fmtPrice(r.entryPrice), AppTheme.textPrimary),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: AppTheme.border, height: 1),
                ),
                _dataRow('Exit price', _fmtPrice(r.exitPrice), AppTheme.textPrimary),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: AppTheme.border, height: 1),
                ),
                _dataRow(
                  'Price change',
                  '${_fmtDelta(r.priceDelta)} (${deltaPct >= 0 ? "+" : ""}${deltaPct.toStringAsFixed(3)}%)',
                  r.exitPrice >= r.entryPrice ? AppTheme.bullish : AppTheme.bearish,
                ),
                if (correct) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: AppTheme.border, height: 1),
                  ),
                  _dataRow(
                    _streak > 1 ? 'Points  (×$_streak streak)' : 'Points earned',
                    '+${r.pointsEarned}',
                    AppTheme.accent,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // New Round button
          GestureDetector(
            onTap: _resetRound,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accent.withOpacity(0.4), width: 1),
              ),
              alignment: Alignment.center,
              child: const Text(
                'New Round',
                style: TextStyle(
                  color: AppTheme.accent,
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
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        Text(value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            )),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // HISTORY
  // ─────────────────────────────────────────────
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
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '$_wins of $_totalRounds correct',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: _history.take(10).toList().reversed.map((r) {
            final c = r.isCorrect ? AppTheme.bullish : AppTheme.bearish;
            return Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.withOpacity(0.25), width: 1),
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
        ..._history.take(5).map((r) {
          final correct   = r.isCorrect;
          final lineColor = correct ? AppTheme.bullish : AppTheme.bearish;
          final delta     = r.exitPrice - r.entryPrice;

          return Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: lineColor.withOpacity(0.5),
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
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${r.prediction == Prediction.up ? "Higher" : "Lower"} · '
                        'Actual ${delta >= 0 ? "+" : ""}${_fmtDelta(delta)}',
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  correct ? '+${r.pointsEarned}' : '—',
                  style: TextStyle(
                    color: correct ? AppTheme.accent : AppTheme.textDim,
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