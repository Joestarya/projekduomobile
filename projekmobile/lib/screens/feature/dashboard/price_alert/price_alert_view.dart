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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel('Coin'),
          const SizedBox(height: 6),
          DropdownButton<int>(
            value: controller.selectedCoinIndex,
            dropdownColor: AppTheme.surfaceHigh,
            underline: const SizedBox.shrink(),
            items: List.generate(PriceAlertController.coins.length, (index) {
              final coin = PriceAlertController.coins[index];
              return DropdownMenuItem(
                value: index,
                child: Text('${coin.emoji} ${coin.symbol}'),
              );
            }),
            onChanged: (value) => controller.selectCoin(value ?? 0),
          ),
          const SizedBox(height: 12),
          _buildFieldLabel('Arah'),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'up', label: Text('Naik')),
              ButtonSegment<String>(value: 'down', label: Text('Turun')),
            ],
            selected: <String>{controller.direction},
            onSelectionChanged: (selection) =>
                controller.setDirection(selection.first),
          ),
          const SizedBox(height: 12),
          _buildFieldLabel('Persenan (%)'),
          const SizedBox(height: 6),
          TextField(
            controller: _percentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: controller.setPercentText,
            decoration: InputDecoration(
              hintText: 'Masukkan %',
              suffixText: '%',
              filled: true,
              fillColor: AppTheme.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                disabledBackgroundColor: AppTheme.textDim,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: controller.canSubmit ? _submit : null,
              child: controller.isSubmitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Set Alert'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertTile(PriceAlertItem alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${alert.coinSymbol} ${alert.direction == 'up' ? '↑' : '↓'} \$${controller.formatPrice(alert.targetPrice)}',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _delete(alert.id),
            icon: const Icon(Icons.close, size: 16),
            color: AppTheme.bearish,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
}
