import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'service/biometric_auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tugas Akhir TPM',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final hasToken = token != null && token.isNotEmpty;

    if (!hasToken) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isAuthenticated = false;
      });
      return;
    }

    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    if (biometricEnabled) {
      final isAuthenticated = await BiometricAuthService.authenticate(
        reason: 'Verifikasi biometrik untuk membuka aplikasi',
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isAuthenticated = isAuthenticated;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isAuthenticated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isAuthenticated) {
      return HomeScreen();
    }

    return LoginScreen();
  }
}
