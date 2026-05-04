import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../service/api_config.dart';

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

class PriceAlertController extends ChangeNotifier {
  PriceAlertController(this.livePrices);

  final Map<String, double> livePrices;

  static const coins = [
    PriceAlertOption(symbol: 'BTC', emoji: '₿'),
    PriceAlertOption(symbol: 'ETH', emoji: 'Ξ'),
    PriceAlertOption(symbol: 'BNB', emoji: 'B'),
    PriceAlertOption(symbol: 'SOL', emoji: '◎'),
  ];

  static const quickPercents = [1, 2, 3, 5, 10, 15, 20];

  final List<PriceAlertItem> alerts = [];

  bool isLoading = true;
  bool isSubmitting = false;
  String? userId;
  int selectedCoinIndex = 0;
  String direction = 'up';
  String percentText = '';

  String get selectedSymbol => coins[selectedCoinIndex].symbol;
  double? get selectedLivePrice => livePrices[selectedSymbol];

  double? get percentValue {
    final value = double.tryParse(percentText.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return value;
  }

  double? get targetPrice {
    final price = selectedLivePrice;
    final percent = percentValue;
    if (price == null || price == 0 || percent == null) return null;
    return direction == 'up'
        ? price * (1 + (percent / 100))
        : price * (1 - (percent / 100));
  }

  bool get canSubmit => targetPrice != null && !isSubmitting;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id');
    if (userId == null) {
      isLoading = false;
      notifyListeners();
      return;
    }
    await fetchAlerts();
  }

  Future<void> fetchAlerts() async {
    if (userId == null) return;
    isLoading = true;
    notifyListeners();
    try {
      final response = await http
          .get(Uri.parse(ApiConfig.endpoint('/alerts?user_id=$userId')))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        alerts
          ..clear()
          ..addAll(
            (data['alerts'] as List)
                .map((item) => PriceAlertItem.fromJson(item as Map<String, dynamic>)),
          );
      }
    } catch (_) {
      // Keep the screen usable even if the network fails.
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectCoin(int index) {
    if (index < 0 || index >= coins.length) return;
    selectedCoinIndex = index;
    notifyListeners();
  }

  void setDirection(String value) {
    if (value == direction) return;
    direction = value;
    notifyListeners();
  }

  void setPercentText(String value) {
    percentText = value;
    notifyListeners();
  }

  void useQuickPercent(double value) {
    percentText = value.toString();
    notifyListeners();
  }

  String formatPrice(double value) {
    return value >= 10 ? value.toStringAsFixed(2) : value.toStringAsFixed(4);
  }

  Future<String?> createAlert() async {
    final price = targetPrice;
    if (userId == null) return 'User belum login';
    if (price == null) return 'Masukkan % custom yang valid';

    isSubmitting = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.endpoint('/alerts')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': int.parse(userId!),
          'coin_symbol': selectedSymbol,
          'target_price': price,
          'direction': direction,
        }),
      );

      if (response.statusCode == 201) {
        percentText = '';
        await fetchAlerts();
        return null;
      }

      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['message']?.toString() ?? 'Gagal membuat alert';
      } catch (_) {
        return 'Gagal membuat alert';
      }
    } catch (_) {
      return 'Koneksi gagal';
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<String?> deleteAlert(int id) async {
    if (userId == null) return 'User belum login';
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.endpoint('/alerts/$id?user_id=$userId')),
      );
      if (response.statusCode == 200) {
        alerts.removeWhere((item) => item.id == id);
        notifyListeners();
        return null;
      }
      return 'Gagal menghapus alert';
    } catch (_) {
      return 'Gagal menghapus alert';
    }
  }
}
