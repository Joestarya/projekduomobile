class AssetItem {
  final String name;
  final String symbol;
  final String pair;
  final double priceUsd;
  final double? prevPriceUsd;
  final double changePercent;
  final List<double> sparkline;

  const AssetItem({
    required this.name,
    required this.symbol,
    required this.pair,
    required this.priceUsd,
    this.prevPriceUsd,
    this.changePercent = 0.0,
    this.sparkline = const [],
  });

  AssetItem copyWithPrev(double prev) => AssetItem(
    name: name,
    symbol: symbol,
    pair: pair,
    priceUsd: priceUsd,
    prevPriceUsd: prev,
    changePercent: changePercent,
    sparkline: sparkline,
  );
}
