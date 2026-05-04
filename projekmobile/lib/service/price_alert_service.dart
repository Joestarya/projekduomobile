import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class PriceAlertService {
  PriceAlertService._();

  static final _notif = FlutterLocalNotificationsPlugin();
  static Timer? _timer;
  static String? _userId;
  static bool _initialized = false;

  // ── Init ──────────────────────────
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(const InitializationSettings(android: androidSettings));

    // Minta izin notif 
    await _notif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // ── Mulai polling setelah login ─────────────────────────
  static void startPolling(String userId) {
    _userId = userId;
    _timer?.cancel();
    _checkAlerts(); // langsung cek sekali
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkAlerts());
  }

  // ── Stop polling saat logout ────────────────────────────
  static void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _userId = null;
  }

  // ── Internal: cek alert ke backend ──────────────────────
  static Future<void> _checkAlerts() async {
    if (_userId == null) return;
    print('[PriceAlert] Checking alerts for user $_userId...');
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.endpoint('/alerts/check?user_id=$_userId')))
          .timeout(const Duration(seconds: 10));
        print('[PriceAlert] Response: ${resp.statusCode} - ${resp.body}');
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      final List triggered = data['triggered'] ?? [];

      for (final alert in triggered) {
        await _showNotification(alert);
        await _markTriggered(alert['id'] as int);
      }
    } catch (_) {
    }
  }

  static Future<void> _showNotification(Map alert) async {
    final symbol    = alert['coin_symbol'] as String;
    final direction = alert['direction'] as String;
    final target    = (alert['target_price'] as num).toDouble();
    final current   = (alert['current_price'] as num).toDouble();

    final emoji   = direction == 'up' ? '📈' : '📉';
    final dirText = direction == 'up' ? 'naik ke atas' : 'turun ke bawah';

    await _notif.show(
      alert['id'] as int,
      '$emoji $symbol Price Alert!',
      'Harga $symbol sudah $dirText \$${_fmt(target)}. Sekarang: \$${_fmt(current)}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'price_alert_channel',
          'Price Alerts',
          channelDescription: 'Notifikasi harga crypto',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> _markTriggered(int alertId) async {
    try {
      await http.patch(
        Uri.parse(ApiConfig.endpoint('/alerts/$alertId/triggered')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': int.parse(_userId!)}),
      );
    } catch (_) {}
  }

  static String _fmt(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1)     return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }
}