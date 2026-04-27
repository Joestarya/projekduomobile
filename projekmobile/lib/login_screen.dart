import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'biometric_auth_service.dart';
import 'register_screen.dart';
import 'screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
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
          content: const Text(
            'Aktifkan Fingerprint?',
          ),
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
    setState(() {
      _isLoading = true;
    });

    final String apiUrl = ApiConfig.endpoint('/login');
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _usernameController.text,
          'password': _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Login Berhasil -> Simpan Token (Kriteria: Session)
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
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
        SnackBar(content: Text('Error: Tidak bisa terhubung ke server')),
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
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                Image.asset(
                  'assets/login.png',
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.person, size: 100);
                  },
                ),
              ],
            ),
            const Text(
              'Login',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RegisterScreen()),
                );
              },
              child: const Text('Belum punya akun? Signup'),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(250, 60),
                    ),
                    child: const Text('Login'),
                  ),
            if (_showBiometricLogin) ...[
              const SizedBox(height: 12),
              _isBiometricLoading
                  ? const CircularProgressIndicator()
                  : OutlinedButton.icon(
                      onPressed: _loginWithBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Login dengan Fingerprint/Face'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(250, 56),
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
