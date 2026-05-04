enum GamePhase { idle, active, resolving, result }

enum Prediction { up, down }

class TimeframeConfig {
  final String label;
  final String interval;
  final int durationSec;
  final int candleLimit;

  const TimeframeConfig(this.label, this.interval, this.durationSec, this.candleLimit);
}

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
