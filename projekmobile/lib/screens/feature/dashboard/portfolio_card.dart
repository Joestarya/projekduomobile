import 'package:flutter/material.dart';
import '../../../models/asset_item.dart';

class PortfolioCard extends StatelessWidget {
  final bool isPrivacyMode;
  final bool isPortfolioConnected;
  final bool isIdrMode;
  final double totalBalance;
  final double idrRate;
  final Map<String, double> userBalances;
  final List<AssetItem> assets;
  final VoidCallback onTogglePrivacy;
  final String Function(double) formatIdr;
  final String Function(double) formatUsd;

  const PortfolioCard({
    super.key,
    required this.isPrivacyMode,
    required this.isPortfolioConnected,
    required this.isIdrMode,
    required this.totalBalance,
    required this.idrRate,
    required this.userBalances,
    required this.assets,
    required this.onTogglePrivacy,
    required this.formatIdr,
    required this.formatUsd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? const Color(0xFF131929),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Portofolio',
                style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 13),
              ),
              GestureDetector(
                onTap: onTogglePrivacy,
                child: Icon(
                  isPrivacyMode ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF8B9BB4),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPrivacyMode
                ? '•••••••••'
                : (!isPortfolioConnected
                      ? 'Data tidak tersedia'
                      : (isIdrMode
                            ? formatIdr(totalBalance * idrRate)
                            : formatUsd(totalBalance))),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...userBalances.entries.where((e) => e.value > 0).map((e) {
                  final displayStr = isPrivacyMode
                      ? '•••'
                      : _formatBalance(e.value);

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildQuickStat(e.key, displayStr),
                  );
                }),
                if (userBalances.isEmpty ||
                    !userBalances.values.any((v) => v > 0))
                  _buildQuickStat('Aset', 'Kosong'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBalance(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(4);
    final fixed = value.toStringAsFixed(8);
    return fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Widget _buildQuickStat(String symbol, String displayValue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$symbol: $displayValue',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}
