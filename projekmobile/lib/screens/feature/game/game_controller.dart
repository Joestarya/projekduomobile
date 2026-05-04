import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../service/api_config.dart';
import 'game_models.dart';

class GameController extends ChangeNotifier {
  // Constants
  static const List<Map<String, String>> assets = [
    {'pair': 'BTCUSDT', 'ticker': 'BTC', 'name': 'Bitcoin'},
    {'pair': 'ETHUSDT', 'ticker': 'ETH', 'name': 'Ethereum'},
    {'pair': 'BNBUSDT', 'ticker': 'BNB', 'name': 'BNB'},
    {'pair': 'SOLUSDT', 'ticker': 'SOL', 'name': 'Solana'},
  ];
  static const Map<String, Color> assetColors = {
    'BTCUSDT': Color(0xFFF7931A),
    'ETHUSDT': Color(0xFF627EEA),
    'BNBUSDT': Color(0xFFF0B90B),
    'SOLUSDT': Color(0xFF9945FF),
  };

  // State
  GamePhase phase = GamePhase.idle;
  Prediction? prediction;
  String selectedPair = 'BTCUSDT';
  double currentPrice = 0;
  double entryPrice = 0;
  double secondsLeft = 0;

  int totalScore = 0;

  RoundResult? lastResult;
  List<Map<String, double>> candles = [];
  final List<RoundResult> history = [];

  bool scoreLoaded = false;
  String? _authToken;

  Timer? priceTimer;
  Timer? countdownTimer;

  GameController() {
    secondsLeft = 30.0;
    _loadScore();
    _fetchPrice();
    _fetchCandles();
    priceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _fetchPrice(),
    );
  }

  @override
  void dispose() {
    priceTimer?.cancel();
    countdownTimer?.cancel();
    super.dispose();
  }

  // --- Methods ---
  Future<String?> _getToken() async {
    if (_authToken != null) return _authToken;
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('token');
    return _authToken;
  }

  Future<void> _loadScore() async {
    final prefs = await SharedPreferences.getInstance();
    totalScore = prefs.getInt('game_total_score') ?? 0;
    notifyListeners();

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
        totalScore = max(
          totalScore,
          (data['total_score'] as num?)?.toInt() ?? 0,
        );
        await _saveScoreLocal();
        notifyListeners();
      }
    } catch (_) {}
    scoreLoaded = true;
  }

  Future<void> _saveScoreLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game_total_score', totalScore);
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
            body: jsonEncode({'total_score': totalScore}),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<void> _fetchPrice() async {
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.endpoint('/crypto/prices')))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final List assets = (body['data'] as List?) ?? [];
      final match = assets.firstWhere(
        (a) => a['pair'] == selectedPair,
        orElse: () => null,
      );
      if (match != null) {
        currentPrice = (match['price'] as num).toDouble();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _fetchCandles() async {
    final urls = [
      ApiConfig.endpoint(
        '/crypto/klines?symbol=$selectedPair&interval=1m&limit=60',
      ),
      'https://api.binance.com/api/v3/klines?symbol=$selectedPair&interval=1m&limit=60',
    ];
    for (final url in urls) {
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        final body = jsonDecode(resp.body);
        final List raw = body is Map ? (body['data'] ?? []) : body;
        candles = raw.map<Map<String, double>>((k) {
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
        notifyListeners();
        return;
      } catch (_) {}
    }
  }

  void startRound(Prediction pred) {
    if (phase != GamePhase.idle || currentPrice == 0) return;
    prediction = pred;
    phase = GamePhase.active;
    entryPrice = currentPrice;
    secondsLeft = 30.0;
    notifyListeners();

    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      secondsLeft -= 0.1;
      if (secondsLeft <= 0) {
        timer.cancel();
        _finalizeRound();
      }
      notifyListeners();
    });
  }

  Future<void> _finalizeRound() async {
    phase = GamePhase.resolving;
    notifyListeners();
    await _fetchPrice();
    await Future.delayed(const Duration(milliseconds: 200));

    final exitPrice = currentPrice;
    final priceWentUp = exitPrice > entryPrice;
    final correct =
        (prediction == Prediction.up && priceWentUp) ||
        (prediction == Prediction.down && !priceWentUp);
    final earned = correct ? 100 : 0;
    final losed = !correct ? 100 : 0;

    final result = RoundResult(
      prediction: prediction!,
      entryPrice: entryPrice,
      exitPrice: exitPrice,
      isCorrect: correct,
      pointsEarned: earned,
      pointsLost: losed,
      timestamp: DateTime.now(),
    );

    phase = GamePhase.result;
    lastResult = result;
    if (correct) {
      totalScore += earned;
    } else {
      totalScore = max(0, totalScore - losed);
    }
    history.insert(0, result);
    if (history.length > 20) history.removeLast();
    notifyListeners();

    await _saveScoreLocal();
    _syncScoreToServer();
    await _fetchCandles();
  }

  void resetRound() {
    phase = GamePhase.idle;
    prediction = null;
    lastResult = null;
    secondsLeft = 30.0;
    notifyListeners();
  }

  void selectPair(String pair) {
    if (phase != GamePhase.idle) return;
    selectedPair = pair;
    currentPrice = 0;
    candles = [];
    notifyListeners();
    _fetchPrice();
    _fetchCandles();
  }
}
