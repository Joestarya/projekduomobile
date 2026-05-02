import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'service/biometric_auth_service.dart';
import 'screens/user/login_screen.dart';
import 'screens/home_screen.dart';
import 'service/price_alert_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PriceAlertService.init(); // ← tambah ini
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tugas Akhir TPM',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E2738),
        primaryColor: const Color(0xFF638BFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF638BFF),
          secondary: Color(0xFF4FA0FF),
          surface: Color(0xFF283548),
          background: Color(0xFF1E2738),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E2738),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1A2232),
          selectedItemColor: Color(0xFF638BFF),
          unselectedItemColor: Color(0xFF6A7B96),
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF283548),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF638BFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF283548),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF638BFF), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8B9BB4)),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF324158),
          thickness: 1,
        ),
        fontFamily: 'Roboto', // Default fallback, but sets a clean vibe
      ),
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
    setState(() { _isLoading = false; _isAuthenticated = false; });
    return;
  }

  final userId = prefs.getString('user_id') ?? ''; // ← tambah ini

  final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
  if (biometricEnabled) {
    final isAuthenticated = await BiometricAuthService.authenticate(
      reason: 'Verifikasi biometrik untuk membuka aplikasi',
    );

    if (isAuthenticated && userId.isNotEmpty) {
      PriceAlertService.startPolling(userId); // ← tambah ini
    }

    if (!mounted) return;
    setState(() { _isLoading = false; _isAuthenticated = isAuthenticated; });
    return;
  }

  if (userId.isNotEmpty) {
    PriceAlertService.startPolling(userId); // ← tambah ini
  }

  if (!mounted) return;
  setState(() { _isLoading = false; _isAuthenticated = true; });
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
