import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import '../api_config.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isPrivacyMode = false;
  double _totalBalance = 950.0; // Saldo dummy, nanti ambil dari database
  bool _isLoadingPrices = true;
  bool _isFetchingPrices = false;
  String? _priceError;
  String? _lastUpdatedAt;
  Timer? _priceRefreshTimer;
  final Map<String, double> _assetPricesUsd = {};

  // 1. Ubah tipe Subscription-nya ke UserAccelerometerEvent
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;

  DateTime _lastShakeTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startShakeDetection();
    _fetchCryptoPrices();
    _priceRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchCryptoPrices(showLoader: false);
    });
  }

  Future<void> _fetchCryptoPrices({bool showLoader = true}) async {
    if (_isFetchingPrices) return;

    if (showLoader) {
      setState(() {
        _isLoadingPrices = true;
        _priceError = null;
      });
    }

    _isFetchingPrices = true;

    try {
      final response = await http.get(
        Uri.parse(ApiConfig.endpoint('/crypto/prices')),
      );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> jsonMap = jsonDecode(response.body);
      final List<dynamic> assets = (jsonMap['data'] as List<dynamic>? ?? []);
      final updatedAt = jsonMap['updatedAt']?.toString();

      final nextPrices = <String, double>{};
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final pair = asset['pair']?.toString();
          final price = num.tryParse(asset['price']?.toString() ?? '');
          if (pair != null && price != null) {
            nextPrices[pair] = price.toDouble();
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _assetPricesUsd
          ..clear()
          ..addAll(nextPrices);
        _lastUpdatedAt = updatedAt;
        _priceError = null;
        _isLoadingPrices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _priceError = 'Harga realtime belum tersedia';
        _isLoadingPrices = false;
      });
    } finally {
      _isFetchingPrices = false;
    }
  }

  void _startShakeDetection() {
    // Plugin sensors_plus belum tersedia di Linux desktop, jadi dinonaktifkan.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    // 2. Gunakan userAccelerometerEvents (TANPA GRAVITASI BUMI)
    _accelerometerSubscription = userAccelerometerEvents.listen((
      UserAccelerometerEvent event,
    ) {
      // Hitung kekuatan gerakan murni dari user
      double gForce = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      // 3. Karena gravitasi udah nggak dihitung, angka 12 ini udah lumayan kencang
      // (Bisa kamu turunkan ke 10 kalau kurang sensitif, atau naikkan ke 15 kalau masih terlalu sensitif)
      if (gForce > 12) {
        DateTime now = DateTime.now();

        // Sistem Cooldown 1.5 detik (Biarkan ini tetap ada biar nggak panik)
        if (now.difference(_lastShakeTime).inMilliseconds > 1500) {
          _lastShakeTime = now;

          setState(() {
            _isPrivacyMode = !_isPrivacyMode;
          });
        }
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _priceRefreshTimer?.cancel();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  String _formatUsd(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final wholeWithCommas = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '\$$wholeWithCommas.${parts[1]}';
  }

  String _formatUpdatedTime(String isoTime) {
    final dt = DateTime.tryParse(isoTime)?.toLocal();
    if (dt == null) return '-';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KARTU PORTOFOLIO
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo, Colors.blueAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Portofolio',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    Icon(
                      _isPrivacyMode ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white70,
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  _isPrivacyMode
                      ? '\$*********'
                      : _formatUsd(_totalBalance),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '+ \$15.30 (1.6%) Today',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 14),
                ),
                SizedBox(height: 5),
                Text(
                  '💡 Info: Goyangkan HP untuk menyembunyikan saldo',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 24),
          Text(
            'Aset Anda',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (_lastUpdatedAt != null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Update: ${_formatUpdatedTime(_lastUpdatedAt!)}',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
          if (_isLoadingPrices)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Memuat harga realtime...',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else if (_priceError != null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                _priceError!,
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          SizedBox(height: 10),

          // LIST ASET dari backend (sumber Tokocrypto)
          Expanded(
            child: ListView(
              children: [
                _buildAssetTile(
                  'Bitcoin',
                  'BTC',
                  0.015,
                  _assetPricesUsd['BTCUSDT'],
                  Colors.orange,
                ),
                _buildAssetTile(
                  'Ethereum',
                  'ETH',
                  0.5,
                  _assetPricesUsd['ETHUSDT'],
                  Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fungsi untuk membuat baris aset
  Widget _buildAssetTile(
    String name,
    String symbol,
    double amount,
    double? priceUsd,
    Color iconColor,
  ) {
    final hasPrice = priceUsd != null;
    final totalValue = hasPrice ? amount * priceUsd : null;

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor,
          child: Text(symbol[0], style: TextStyle(color: Colors.white)),
        ),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(hasPrice ? _formatUsd(priceUsd) : 'Harga belum tersedia'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _isPrivacyMode
                  ? '\$*****'
                  : (totalValue != null ? _formatUsd(totalValue) : '\$--'),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
