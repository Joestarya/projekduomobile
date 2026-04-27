import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import '../service/api_config.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _AssetItem {
  final String name;
  final String symbol;
  final String pair;
  final double priceUsd;

  const _AssetItem({
    required this.name,
    required this.symbol,
    required this.pair,
    required this.priceUsd,
  });
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _priceRefreshInterval = Duration(seconds: 1);

  bool _isPrivacyMode = false;
  double _totalBalance = 950.0; // Saldo dummy, nanti ambil dari database
  bool _isLoadingPrices = true;
  bool _isFetchingPrices = false;
  bool _hasPendingPriceFetch = false;
  String? _priceError;
  String? _lastUpdatedAt;
  Timer? _priceRefreshTimer;
  List<_AssetItem> _assets = const [];

  // 1. Ubah tipe Subscription-nya ke UserAccelerometerEvent
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;

  DateTime _lastShakeTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startShakeDetection();
    _requestPriceFetch(showLoader: true);
    _priceRefreshTimer = Timer.periodic(_priceRefreshInterval, (_) {
      _requestPriceFetch(showLoader: false);
    });
  }

  void _requestPriceFetch({required bool showLoader}) {
    if (_isFetchingPrices) {
      _hasPendingPriceFetch = true;
      return;
    }
    _fetchCryptoPrices(showLoader: showLoader);
  }

  Future<void> _fetchCryptoPrices({bool showLoader = true}) async {
    _isFetchingPrices = true;

    if (showLoader) {
      setState(() {
        _isLoadingPrices = true;
        _priceError = null;
      });
    }

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

      final nextAssets = <_AssetItem>[];
      for (final asset in assets) {
        if (asset is! Map) continue;

        final name = asset['name']?.toString();
        final symbol = asset['symbol']?.toString();
        final pair = asset['pair']?.toString();
        final price = num.tryParse(asset['price']?.toString() ?? '');

        if (name == null || symbol == null || pair == null || price == null) {
          continue;
        }

        nextAssets.add(
          _AssetItem(
            name: name,
            symbol: symbol,
            pair: pair,
            priceUsd: price.toDouble(),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _assets = nextAssets;
        _lastUpdatedAt = updatedAt;
        _priceError = assets.isNotEmpty && nextAssets.isEmpty
            ? 'Format data aset tidak sesuai'
            : null;
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

      if (_hasPendingPriceFetch) {
        _hasPendingPriceFetch = false;
        _requestPriceFetch(showLoader: false);
      }
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

  void _togglePrivacyMode() {
    setState(() {
      _isPrivacyMode = !_isPrivacyMode;
    });
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
                    IconButton(
                      tooltip: _isPrivacyMode
                          ? 'Tampilkan saldo'
                          : 'Sembunyikan saldo',
                      onPressed: _togglePrivacyMode,
                      icon: Icon(
                        _isPrivacyMode
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  _isPrivacyMode ? '\$*********' : _formatUsd(_totalBalance),
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
                  'Info: Ketuk ikon mata atau goyangkan HP untuk hide/show saldo',
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
            'TOP ASSETS',
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

          Expanded(
            child: _assets.isEmpty
                ? Center(
                    child: Text(
                      'Belum ada data aset dari server',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.builder(
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      return _buildAssetTile(_assets[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _iconColorForSymbol(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return Colors.orange;
      case 'ETH':
        return Colors.blue;
      default:
        return Colors.indigo;
    }
  }

  // Fungsi untuk membuat baris aset
  Widget _buildAssetTile(_AssetItem asset) {
    final iconColor = _iconColorForSymbol(asset.symbol);

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor,
          child: Text(asset.symbol[0], style: TextStyle(color: Colors.white)),
        ),
        title: Text(asset.name, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(asset.pair),
        trailing: Text(
          _formatUsd(asset.priceUsd),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
