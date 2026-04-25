import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isPrivacyMode = false;
  double _totalBalance = 15450000.0; // Saldo dummy, nanti ambil dari database
  
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  @override
  void initState() {
    super.initState();
    _startShakeDetection();
  }

  void _startShakeDetection() {
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      // Menghitung kekuatan guncangan
      double gForce = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      // Jika guncangan melebihi ambang batas (misal 15), aktifkan/matikan Privacy Mode
      if (gForce > 15) {
        setState(() {
          _isPrivacyMode = !_isPrivacyMode;
        });
        // Jeda sedikit biar nggak kedap-kedip kalau digoyang terus
        _accelerometerSubscription?.pause();
        Future.delayed(Duration(seconds: 2), () {
          _accelerometerSubscription?.resume();
        });
      }
    });
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    super.dispose();
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
                    )
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  _isPrivacyMode ? 'Rp *********' : 'Rp ${_totalBalance.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '+ Rp 1.250.000 (8.5%) Hari Ini',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 14),
                ),
                SizedBox(height: 5),
                Text(
                  '💡 Info: Goyangkan HP untuk menyembunyikan saldo',
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 24),
          Text('Aset Anda', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          
          // LIST ASET (Contoh Statis)
          Expanded(
            child: ListView(
              children: [
                _buildAssetTile('Bitcoin', 'BTC', 0.015, 1050000000, Colors.orange),
                _buildAssetTile('Ethereum', 'ETH', 0.5, 45000000, Colors.blue),
              ],
            ),
          )
        ],
      ),
    );
  }

  // Fungsi untuk membuat baris aset
  Widget _buildAssetTile(String name, String symbol, double amount, double price, Color iconColor) {
    double totalValue = amount * price;
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconColor, child: Text(symbol[0], style: TextStyle(color: Colors.white))),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$amount $symbol'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _isPrivacyMode ? 'Rp *****' : 'Rp ${totalValue.toStringAsFixed(0)}', 
              style: TextStyle(fontWeight: FontWeight.bold)
            ),
          ],
        ),
      ),
    );
  }
}