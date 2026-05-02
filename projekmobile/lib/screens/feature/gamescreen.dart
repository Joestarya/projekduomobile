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
// ENUMS & MODELS
// ─────────────────────────────────────────────
enum GamePhase { idle, active, resolving, result }

enum Prediction { up, down }

// ── Timeframe config ──────────────────────────
class _TF {
  final String label;      // "1m" / "5m" / "15m"
  final String interval;   // Binance interval param
  final int durationSec;   // durasi round (detik)
  final int candleLimit;   // jumlah candle di-fetch

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
    final allLow  = candles.map((c) => c['low']!).reduce(min);
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
      final c  = candles[i];
      final cx = i * spacing + spacing / 2;
      final isUp = c['close']! >= c['open']!;
      final bodyColor =
          isUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

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
          Rect.fromLTWH(
              cx - candleW / 2, bTop, candleW, max(bBot - bTop, 1.0)),
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
  // SCORE PERSISTENCE  (SharedPrefs sebagai cache lokal + sync ke API)
  // ─────────────────────────────────────────────

  /// Ambil token dari SharedPreferences (disimpan saat login)
  Future<String?> _getToken() async {
    if (_authToken != null) return _authToken;
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('token');
    return _authToken;
  }

  /// Load score: coba dari API dulu, fallback ke SharedPrefs lokal
  Future<void> _loadScore() async {
    // 1) Coba load dari SharedPrefs lokal dulu (agar UI cepat muncul)
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _totalScore  = prefs.getInt('game_total_score')  ?? 0;
      _totalRounds = prefs.getInt('game_total_rounds') ?? 0;
      _wins        = prefs.getInt('game_total_wins')   ?? 0;
      _bestStreak  = prefs.getInt('game_best_streak')  ?? 0;
    });

    // 2) Sync dari server (lebih akurat, misalnya user pakai 2 device)
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
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final serverScore  = (data['total_score']  as num?)?.toInt() ?? 0;
        final serverRounds = (data['total_rounds'] as num?)?.toInt() ?? 0;
        final serverWins   = (data['total_wins']   as num?)?.toInt() ?? 0;
        final serverBest   = (data['best_streak']  as num?)?.toInt() ?? 0;

        // Pakai nilai terbesar antara lokal & server
        if (mounted) {
          setState(() {
            _totalScore  = max(_totalScore,  serverScore);
            _totalRounds = max(_totalRounds, serverRounds);
            _wins        = max(_wins,        serverWins);
            _bestStreak  = max(_bestStreak,  serverBest);
          });
        }

        // Update cache lokal agar konsisten
        await _saveScoreLocal();
      }
    } catch (_) {
      // Tidak ada internet / server mati → tetap pakai data lokal
    }

    _scoreLoaded = true;
  }

  /// Simpan ke SharedPreferences (cache lokal)
  Future<void> _saveScoreLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game_total_score',  _totalScore);
    await prefs.setInt('game_total_rounds', _totalRounds);
    await prefs.setInt('game_total_wins',   _wins);
    await prefs.setInt('game_best_streak',  _bestStreak);
  }

  /// Kirim score ke server (fire-and-forget, tidak blokir UI)
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
    } catch (_) {
      // Gagal sync → sudah tersimpan lokal, akan sync lagi nanti
    }
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

    final exitPrice   = _currentPrice;
    final priceWentUp = exitPrice > _entryPrice;
    final correct = (_prediction == Prediction.up  &&  priceWentUp) ||
                    (_prediction == Prediction.down && !priceWentUp);
    final earned  = correct ? 100 + (_streak * 20) : 0;

    HapticFeedback.lightImpact();

    final result = RoundResult(
      prediction:   _prediction!,
      entryPrice:   _entryPrice,
      exitPrice:    exitPrice,
      isCorrect:    correct,
      pointsEarned: earned,
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
        _streak = 0;
      }
      _history.insert(0, result);
      if (_history.length > 20) _history.removeLast();
    });

    // Simpan lokal dulu (cepat), lalu sync ke server
    await _saveScoreLocal();
    _syncScoreToServer(); // fire-and-forget

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

  /// Ganti timeframe — hanya boleh saat idle
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

  /// Format detik menjadi "4:32" atau "14:59"
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                      // ── TIMEFRAME SELECTOR ──
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
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context).dividerTheme.color ??
                    Colors.transparent,
                width: 1)),
      ),
      child: Row(
        children: [
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
                  style:
                      TextStyle(color: Color(0xFF2A3A5A), fontSize: 11),
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

  // ─────────────────────────────────────────────
  // TIMEFRAME TABS  ← NEW
  // ─────────────────────────────────────────────
  Widget _buildTimeframeTabs() {
    final isDisabled = _phase != GamePhase.idle;
    return Row(
      children: [
        const Text(
          'TIMEFRAME',
          style: TextStyle(
            color: Color(0xFF1A2535),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF26A69A).withOpacity(0.12)
                    : const Color(0xFF0C1018),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF26A69A).withOpacity(0.4)
                      : const Color(0xFF0E1420),
                  width: 1,
                ),
              ),
              child: Text(
                tf.label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF26A69A)
                      : isDisabled
                          ? const Color(0xFF1A2535)
                          : const Color(0xFF3A5070),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1018),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: const Color(0xFF1A2535), width: 1),
            ),
            child: const Text(
              'Locked during round',
              style:
                  TextStyle(color: Color(0xFF1A2535), fontSize: 9),
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
              margin:
                  EdgeInsets.only(right: i < _assets.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withOpacity(0.07)
                    : Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? accentColor.withOpacity(0.3)
                      : Theme.of(context).dividerTheme.color ??
                          Colors.transparent,
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
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).dividerTheme.color ??
                Colors.transparent,
            width: 1),
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
                  color: accentColor.withOpacity(0.15), width: 1),
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
                '${meta['ticker']!}/USDT · ${_tf.label}',
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

  // ─────────────────────────────────────────────
  // CHART
  // ─────────────────────────────────────────────
  Widget _buildChart() {
    return Container(
      height: 130,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).dividerTheme.color ??
                Colors.transparent,
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_tf.label.toUpperCase()} CANDLES',
                style: const TextStyle(
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
                  style:
                      TextStyle(color: Color(0xFF1A2535), fontSize: 9),
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
          style: const TextStyle(color: Color(0xFF3A5070), fontSize: 13),
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
            Icon(Icons.info_outline_rounded,
                size: 11, color: Color(0xFF1A2535)),
            SizedBox(width: 5),
            Text(
              '+100 pts base  ·  +20 pts per streak level',
              style:
                  TextStyle(color: Color(0xFF1A2535), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _forecastButton(Prediction pred) {
    final isUp    = pred == Prediction.up;
    final color   = isUp
        ? const Color(0xFF26A69A)
        : const Color(0xFFEF5350);

    return GestureDetector(
      onTap: () => _startRound(pred),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1018),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: color.withOpacity(0.18), width: 1),
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

  // ── ACTIVE ───────────────────────────────────
  Widget _buildActivePanel() {
    final progress  = _secondsLeft / _tf.durationSec;
    final isUp      = _prediction == Prediction.up;
    final delta     = _currentPrice - _entryPrice;
    final onTrack   = (isUp && delta > 0) || (!isUp && delta < 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  // Tampilkan m:ss untuk timeframe > 1m
                  Text(
                    _tf.durationSec > 60
                        ? _fmtCountdown(_secondsLeft)
                        : _secondsLeft.ceil().toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: _tf.durationSec > 60 ? 11 : 17,
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
                  'Resolves in ${_fmtCountdown(_secondsLeft)}',
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
                const SizedBox(height: 2),
                Text(
                  'Timeframe: ${_tf.label}',
                  style: const TextStyle(
                      color: Color(0xFF1A2535), fontSize: 10),
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
              _phase       = GamePhase.idle;
              _prediction  = null;
              _secondsLeft = _tf.durationSec.toDouble();
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2A3A5A),
            minimumSize: Size.zero,
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Cancel round',
              style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── RESOLVING ────────────────────────────────
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

  // ── RESULT ───────────────────────────────────
  Widget _buildResultPanel() {
    final r           = _lastResult!;
    final correct     = r.isCorrect;
    final accentColor = correct
        ? const Color(0xFF26A69A)
        : const Color(0xFFEF5350);
    final deltaPct = r.entryPrice == 0
        ? 0.0
        : ((r.exitPrice - r.entryPrice) / r.entryPrice) * 100;

    return FadeTransition(
      opacity: _resultFade,
      child: Column(
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
                        color: Color(0xFF2A3A5A), fontSize: 11),
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
              border: Border.all(
                  color: const Color(0xFF0E1420), width: 1),
            ),
            child: Column(
              children: [
                _dataRow(
                    'Entry price', _fmtPrice(r.entryPrice), Colors.white),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF0E1420), height: 1),
                ),
                _dataRow(
                    'Exit price', _fmtPrice(r.exitPrice), Colors.white),
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
                border:
                    Border.all(color: c.withOpacity(0.2), width: 1),
              ),
              child: Icon(
                r.isCorrect
                    ? Icons.north_rounded
                    : Icons.south_rounded,
                color: c,
                size: 10,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        ..._history.take(5).map((r) {
          final correct   = r.isCorrect;
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