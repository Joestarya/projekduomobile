enum GamePhase { idle, active, resolving, result }

enum Prediction { up, down }

class RoundResult {
  final Prediction prediction;
  final double entryPrice;
  final double exitPrice;
  final bool isCorrect;

  const RoundResult({
    required this.prediction,
    required this.entryPrice,
    required this.exitPrice,
    required this.isCorrect,
  });
}