import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../service/api_config.dart';
import '../../../service/biometric_auth_service.dart';
import 'register_screen.dart';
import '../../../service/price_alert_service.dart';
import '../../home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showBiometricLogin = false;
  bool _isBiometricLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricAvailability();
  }

  Future<void> _loadBiometricAvailability() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final canAuthenticate = await BiometricAuthService.canAuthenticate();

    if (!mounted) return;
    setState(() {
      _showBiometricLogin =
          token != null &&
          token.isNotEmpty &&
          biometricEnabled &&
          canAuthenticate;
    });
  }

  Future<void> _loginWithBiometric() async {
    setState(() {
      _isBiometricLoading = true;
    });

    final bool isAuthenticated = await BiometricAuthService.authenticate(
      reason: 'Verifikasi biometrik untuk masuk ke akun Anda',
    );

    if (!mounted) return;
    setState(() {
      _isBiometricLoading = false;
    });

    if (isAuthenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Autentikasi biometrik gagal atau dibatalkan'),
        ),
      );
    }
  }

  Future<void> _maybeEnableBiometricAfterLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyEnabled = prefs.getBool('biometric_enabled') ?? false;
    if (alreadyEnabled) return;

    final canAuthenticate = await BiometricAuthService.canAuthenticate();
    if (!canAuthenticate || !mounted) return;

    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Aktifkan Autentikasi Biometrik'),
          content: const Text('Aktifkan Fingerprint?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Nanti'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aktifkan'),
            ),
          ],
        );
      },
    );

    if (shouldEnable != true) return;

    final isAuthenticated = await BiometricAuthService.authenticate(
      reason: 'Verifikasi untuk mengaktifkan login biometrik',
    );

    if (!mounted) return;
    if (isAuthenticated) {
      await prefs.setBool('biometric_enabled', true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login biometrik berhasil diaktifkan')),
      );
      await _loadBiometricAvailability();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktivasi biometrik dibatalkan')),
      );
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username dan password wajib diisi')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final String apiUrl = ApiConfig.endpoint('/login');
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        // Login Berhasil -> Simpan Token (Kriteria: Session)
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final token = (data['token'] ?? '').toString();

        if (token.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Token login tidak valid dari server'),
            ),
          );
          return;
        }

        await prefs.setString('token', token);
        if (data['user'] != null) {
          await prefs.setString(
            'user_id',
            (data['user']['id'] ?? '').toString(),
          );
          await prefs.setString('username', data['user']['username'] ?? '');
          await prefs.setString('full_name', data['user']['full_name'] ?? '');
          PriceAlertService.startPolling((data['user']['id'] ?? '').toString());
        }

        await _maybeEnableBiometricAfterLogin();

        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login Berhasil!')));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen()),
        );
      } else {
        if (!mounted) return;
        // Login Gagal
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Gagal login')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Tidak bisa terhubung ke server')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.lock_person_rounded,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome Back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Login to continue',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF8B9BB4)),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: Color(0xFF8B9BB4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: Color(0xFF8B9BB4),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              if (_showBiometricLogin) ...[
                const SizedBox(height: 16),
                _isBiometricLoading
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton.icon(
                        onPressed: _loginWithBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Login dengan Biometrik'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF638BFF),
                          side: const BorderSide(color: Color(0xFF638BFF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
              ],
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterScreen(),
                    ),
                  );
                },
                child: const Text(
                  'Belum punya akun? Daftar',
                  style: TextStyle(color: Color(0xFF638BFF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
