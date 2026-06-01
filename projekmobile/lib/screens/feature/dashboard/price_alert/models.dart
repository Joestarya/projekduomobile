class PriceAlertOption {
  final String symbol;
  final String emoji;

  const PriceAlertOption({required this.symbol, required this.emoji});
}

class PriceAlertItem {
  final int id;
  final String coinSymbol;
  final double targetPrice;
  final String direction;
  final String status;

  const PriceAlertItem({
    required this.id,
    required this.coinSymbol,
    required this.targetPrice,
    required this.direction,
    required this.status,
  });

  factory PriceAlertItem.fromJson(Map<String, dynamic> json) {
    return PriceAlertItem(
      id: json['id'] as int,
      coinSymbol: json['coin_symbol'] as String,
      targetPrice: double.parse(json['target_price'].toString()),
      direction: json['direction'] as String,
      status: json['status'] as String,
    );
  }
}
