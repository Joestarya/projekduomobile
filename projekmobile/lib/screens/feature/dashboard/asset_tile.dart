import 'package:flutter/material.dart';
import '../../../models/asset_item.dart';
import 'chart.dart';

class AssetTile extends StatelessWidget {
  final AssetItem asset;
  final Color? flashColor;
  final List<double>? sparkData;
  final double userBalance;
  final String priceDisplay;
  final String changePercentDisplay;
  final VoidCallback onTap;

  const AssetTile({
    super.key,
    required this.asset,
    required this.flashColor,
    required this.sparkData,
    required this.userBalance,
    required this.priceDisplay,
    required this.changePercentDisplay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = asset.changePercent >= 0;
    final priceColor = flashColor != null
        ? (flashColor == Colors.greenAccent
              ? const Color(0xFF00E676)
              : const Color(0xFFFF5252))
        : (isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252));

    final hasChart = sparkData != null && sparkData!.length > 2;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: flashColor != null
              ? flashColor!.withOpacity(0.04)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  asset.symbol.length > 2 ? asset.symbol[0] : asset.symbol,
                  style: const TextStyle(
                    color: Color(0xFF9D97FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name & Pair
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.symbol,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      userBalance > 0
                          ? '${_formatBalance(userBalance)} ${asset.symbol}'
                          : asset.name,
                      style: TextStyle(
                        color: userBalance > 0
                            ? const Color(0xFF6C63FF)
                            : const Color(0xFF8B9BB4),
                        fontSize: 12,
                        fontWeight: userBalance > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),

              // Mini Chart
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    height: 44,
                    child: hasChart
                        ? CustomPaint(
                            painter: SparklinePainter(
                              data: sparkData!,
                              isUp: isUp,
                            ),
                          )
                        : _buildLoadingChart(isUp),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Price & %
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: priceColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: -0.3,
                      ),
                      child: Text(
                        priceDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      changePercentDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isUp
                            ? const Color(0xFF00E676)
                            : const Color(0xFFFF5252),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBalance(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(4);
    final fixed = value.toStringAsFixed(8);
    return fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Widget _buildLoadingChart(bool isUp) {
    return Center(
      child: LinearProgressIndicator(
        backgroundColor: const Color(0xFF1A2035),
        valueColor: AlwaysStoppedAnimation<Color>(
          isUp
              ? const Color(0xFF00E676).withOpacity(0.25)
              : const Color(0xFFFF5252).withOpacity(0.25),
        ),
      ),
    );
  }
}
