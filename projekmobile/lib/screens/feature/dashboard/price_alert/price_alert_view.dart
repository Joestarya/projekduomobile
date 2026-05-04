import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import 'price_alert_controller.dart';

class PriceAlertView extends StatefulWidget {
  final PriceAlertController controller;

  const PriceAlertView({super.key, required this.controller});

  @override
  State<PriceAlertView> createState() => _PriceAlertViewState();
}

class _PriceAlertViewState extends State<PriceAlertView> {
  late final TextEditingController _percentController;

  PriceAlertController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(text: controller.percentText);
    controller.addListener(_syncInput);
  }

  @override
  void dispose() {
    controller.removeListener(_syncInput);
    _percentController.dispose();
    super.dispose();
  }

  void _syncInput() {
    if (_percentController.text == controller.percentText) return;
    _percentController.value = _percentController.value.copyWith(
      text: controller.percentText,
      selection: TextSelection.collapsed(offset: controller.percentText.length),
      composing: TextRange.empty,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.bearish : AppTheme.bullish,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _submit() async {
    final error = await controller.createAlert();
    if (!mounted) return;
    if (error == null) {
      _showMessage('Alert berhasil dibuat');
      return;
    }
    _showMessage(error, isError: true);
  }

  Future<void> _delete(int id) async {
    final error = await controller.deleteAlert(id);
    if (!mounted) return;
    if (error == null) {
      _showMessage('Alert dihapus');
      return;
    }
    _showMessage(error, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(
            title: const Text('Price Alert'),
            backgroundColor: AppTheme.surface,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: controller.fetchAlerts,
              ),
            ],
          ),
          body: controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildForm(),
                      const SizedBox(height: 24),
                      Text(
                        'Alert Aktif (${controller.alerts.length})',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (controller.alerts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'Belum ada alert',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                          ),
                        )
                      else
                        ...controller.alerts.map(_buildAlertTile),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildForm() {
    final livePrice = controller.selectedLivePrice;
    final targetPrice = controller.targetPrice;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(
                'Buat alert baru',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildFieldLabel('Coin'),
              ),
              DropdownButton<int>(
                value: controller.selectedCoinIndex,
                dropdownColor: AppTheme.surfaceHigh,
                underline: const SizedBox.shrink(),
                items: List.generate(
                  PriceAlertController.coins.length,
                  (index) {
                    final coin = PriceAlertController.coins[index];
                    return DropdownMenuItem(
                      value: index,
                      child: Text('${coin.emoji} ${coin.symbol}'),
                    );
                  },
                ),
                onChanged: (value) => controller.selectCoin(value ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildFieldLabel('Arah')),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'up', label: Text('Naik')),
              ButtonSegment<String>(value: 'down', label: Text('Turun')),
            ],
            selected: <String>{controller.direction},
            onSelectionChanged: (selection) => controller.setDirection(selection.first),
          ),
          const SizedBox(height: 14),
          _buildFieldLabel('Custom %'),
          const SizedBox(height: 8),
          TextField(
            controller: _percentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: controller.setPercentText,
            decoration: InputDecoration(
              hintText: 'Contoh 2.5',
              suffixText: '%',
              filled: true,
              fillColor: AppTheme.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PriceAlertController.quickPercents.map((percent) {
              final selected = controller.percentValue == percent;
              return ChoiceChip(
                label: Text('${percent.toStringAsFixed(0)}%'),
                selected: selected,
                onSelected: (_) {
                  controller.useQuickPercent(percent.toDouble());
                  _syncInput();
                },
                backgroundColor: AppTheme.surfaceHigh,
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  color: selected ? AppTheme.bg : AppTheme.textPrimary,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
          if (livePrice != null) ...[
            const SizedBox(height: 16),
            _buildPreviewRow('Live', '\$${controller.formatPrice(livePrice)}'),
          ],
          if (targetPrice != null) ...[
            const SizedBox(height: 8),
            _buildPreviewRow('Target', '\$${controller.formatPrice(targetPrice)}', accent: true),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                disabledBackgroundColor: AppTheme.textDim,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: controller.canSubmit ? _submit : null,
              child: controller.isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Set Alert',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertTile(PriceAlertItem alert) {
    final livePrice = controller.livePrices[alert.coinSymbol];
    final distanceText = livePrice == null || livePrice == 0
        ? '—'
        : '${(((alert.targetPrice - livePrice) / livePrice) * 100).toStringAsFixed(1)}%';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              alert.direction == 'up' ? Icons.trending_up : Icons.trending_down,
              color: alert.direction == 'up' ? AppTheme.bullish : AppTheme.bearish,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.coinSymbol} • ${alert.direction == 'up' ? 'Naik' : 'Turun'}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Target \$${controller.formatPrice(alert.targetPrice)} • Selisih $distanceText',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(alert.id),
            icon: const Icon(Icons.close),
            color: AppTheme.bearish,
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: accent ? AppTheme.accent : AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
