import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../widgets/ai_prediction_card.dart';
import '../../../theme/app_theme.dart';
import 'game_models.dart';
import 'game_controller.dart';
import '../dashboard/chart.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GameController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmtPrice(double v) {
    if (v == 0) return '—';
    if (v >= 1) return '\$${v.toStringAsFixed(2)}';
    return '\$${v.toStringAsFixed(4)}';
  }

  String _fmtDelta(double v) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(4)}';
  }

  String _fmtCountdown(double sec) {
    final m = sec.ceil() ~/ 60;
    final r = sec.ceil() % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            title: const Text(
              'Trading Game',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStats(),
                const SizedBox(height: 16),
                _buildControls(),
                const SizedBox(height: 16),
                _buildChart(),
                const SizedBox(height: 16),
                _buildGameAction(),
                if (_controller.phase == GamePhase.result) _buildResult(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStats() {
    return Card(
      color: AppTheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem(
              'Score',
              _controller.totalScore.toString(),
              Colors.yellow,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String val, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      dropdownColor: AppTheme.surfaceHigh,
      value: _controller.selectedPair,
      items: GameController.assets.map((a) {
        return DropdownMenuItem(
          value: a['pair'],
          child: Text(
            a['ticker']!,
            style: const TextStyle(color: Colors.white),
          ),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) _controller.selectPair(v);
      },
    );
  }

  Widget _buildChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: SparklinePainter(
              data: _controller.candles.map((c) => c['close']!).toList(),
              isUp:
                  _controller.candles.isNotEmpty &&
                  (_controller.candles.last['close']! >=
                      _controller.candles.first['close']!),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Text(
              _fmtPrice(_controller.currentPrice),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameAction() {
    final isIdle = _controller.phase == GamePhase.idle;
    final isActive = _controller.phase == GamePhase.active;

    if (isActive) {
      final progress = _controller.secondsLeft / 30.0;
      return Column(
        children: [
          SizedBox(
            height: 100,
            width: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(100, 100),
                  painter: TimerArcPainter(progress: progress),
                ),
                Text(
                  _fmtCountdown(_controller.secondsLeft),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Prediksi Anda: ${_controller.prediction == Prediction.up ? "NAIK" : "TURUN"}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (isIdle)
          AiPredictionCard(
            selectedPair: _controller.selectedPair,
            timeframe: '1m',
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.bullish,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.arrow_upward, color: Colors.white),
                label: const Text(
                  'NAIK',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onPressed: isIdle
                    ? () {
                        HapticFeedback.selectionClick();
                        _controller.startRound(Prediction.up);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.bearish,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.arrow_downward, color: Colors.white),
                label: const Text(
                  'TURUN',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onPressed: isIdle
                    ? () {
                        HapticFeedback.selectionClick();
                        _controller.startRound(Prediction.down);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResult() {
    final res = _controller.lastResult;
    if (res == null) return const SizedBox();

    return Card(
      color: res.isCorrect
          ? Colors.green.withOpacity(0.2)
          : Colors.red.withOpacity(0.2),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              res.isCorrect ? '✅ Benar!' : '❌ Salah',
              style: TextStyle(
                color: res.isCorrect ? Colors.green : Colors.red,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Entry: ${_fmtPrice(res.entryPrice)} | Exit: ${_fmtPrice(res.exitPrice)}',
              style: const TextStyle(color: Colors.white),
            ),
            Text(
              'Perubahan: ${_fmtDelta(res.priceDelta)} (${res.priceDeltaPct.toStringAsFixed(2)}%)',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              res.isCorrect
                  ? '+${res.pointsEarned} Poin'
                  : '-${res.pointsLost} Poin',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _controller.resetRound();
              },
              child: const Text('Main Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class TimerArcPainter extends CustomPainter {
  final double progress;

  const TimerArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;

    // Track ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppTheme.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final Color arcColor;
    if (progress > 0.5) {
      arcColor = AppTheme.bullish;
    } else if (progress > 0.25) {
      arcColor = Color.lerp(
        AppTheme.warning,
        AppTheme.bullish,
        (progress - 0.25) * 4,
      )!;
    } else {
      arcColor = Color.lerp(AppTheme.bearish, AppTheme.warning, progress * 4)!;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(TimerArcPainter o) => o.progress != progress;
}
