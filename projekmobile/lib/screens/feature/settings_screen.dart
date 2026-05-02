import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../user/login_screen.dart';
import '../../service/biometric_auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = false;
  bool _canUseBiometric = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final canUse = await BiometricAuthService.canAuthenticate();
    setState(() {
      _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      _canUseBiometric = canUse;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final isAuthenticated = await BiometricAuthService.authenticate(
        reason: 'Verifikasi untuk mengaktifkan login biometrik',
      );
      if (!isAuthenticated) return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', value);
    setState(() {
      _biometricEnabled = value;
    });
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setting')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          const Text(
            'Preferences',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF8B9BB4),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.notifications_outlined,
                    color: Color(0xFF638BFF),
                  ),
                  title: const Text('Notifikasi'),
                  subtitle: const Text(
                    'Atur pengingat dan notifikasi aplikasi',
                    style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 12),
                  ),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.lock_outline,
                    color: Color(0xFF638BFF),
                  ),
                  title: const Text('Privasi'),
                  subtitle: const Text(
                    'Kelola preferensi privasi akun',
                    style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 12),
                  ),
                  onTap: () {},
                ),
                if (_canUseBiometric) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(
                      Icons.fingerprint,
                      color: Color(0xFF638BFF),
                    ),
                    title: const Text('Login Biometrik'),
                    subtitle: const Text(
                      'Gunakan fingerprint / face ID',
                      style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 12),
                    ),
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
                    activeColor: const Color(0xFF638BFF),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _logout(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.logout),
            label: const Text(
              'Logout',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
