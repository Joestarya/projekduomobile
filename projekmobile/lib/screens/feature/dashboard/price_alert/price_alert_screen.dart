import 'package:flutter/material.dart';

import 'price_alert_controller.dart';
import 'price_alert_view.dart';

class PriceAlertScreen extends StatefulWidget {
  final Map<String, double> livePrices;

  const PriceAlertScreen({super.key, required this.livePrices});

  @override
  State<PriceAlertScreen> createState() => _PriceAlertScreenState();
}

class _PriceAlertScreenState extends State<PriceAlertScreen> {
  late final PriceAlertController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PriceAlertController(widget.livePrices)..init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PriceAlertView(controller: _controller);
  }
}
