import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

import 'map_screen.dart';
import 'gamescreen.dart';

// ─────────────────────────────────────────────
// TIMEZONE DATA
// ─────────────────────────────────────────────
class _TimezoneOption {
  final String label;
  final String city;
  final int offsetHours;
  final int offsetMinutes;

  const _TimezoneOption({
    required this.label,
    required this.city,
    required this.offsetHours,
    this.offsetMinutes = 0,
  });

  DateTime now() {
    final utc = DateTime.now().toUtc();
    return utc.add(Duration(hours: offsetHours, minutes: offsetMinutes));
  }
}

const List<_TimezoneOption> _timezones = [
  _TimezoneOption(label: 'WIB', city: 'Jakarta', offsetHours: 7),
  _TimezoneOption(label: 'WITA', city: 'Makassar', offsetHours: 8),
  _TimezoneOption(label: 'WIT', city: 'Jayapura', offsetHours: 9),
  _TimezoneOption(label: 'UTC', city: 'London', offsetHours: 0),
  _TimezoneOption(label: 'EST', city: 'New York', offsetHours: -5),
  _TimezoneOption(label: 'CST', city: 'Chicago', offsetHours: -6),
  _TimezoneOption(label: 'PST', city: 'Los Angeles', offsetHours: -8),
  _TimezoneOption(label: 'CET', city: 'Paris', offsetHours: 1),
  _TimezoneOption(
    label: 'IST',
    city: 'Mumbai',
    offsetHours: 5,
    offsetMinutes: 30,
  ),
  _TimezoneOption(label: 'SGT', city: 'Singapore', offsetHours: 8),
  _TimezoneOption(label: 'JST', city: 'Tokyo', offsetHours: 9),
  _TimezoneOption(label: 'AEST', city: 'Sydney', offsetHours: 10),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  _TimezoneOption _selectedTimezone = _timezones[0];
  String _clockDisplay = '';
  String _dateDisplay = '';
  Timer? _clockTimer;

  // Daftar halaman untuk Bottom Navigation
  static final List<Widget> _widgetOptions = <Widget>[
    DashboardScreen(),
    GameScreen(),
    AtmFinderScreen(),
    ProfileMenu(), // Menu Profil & Saran Kesan (Wajib Tugas Akhir)
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _startClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
  }

  void _updateClock() {
    if (!mounted) return;
    final now = _selectedTimezone.now();
    setState(() {
      _clockDisplay =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      _dateDisplay =
          '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
    });
  }

  void _onTimezoneChanged(_TimezoneOption tz) {
    setState(() => _selectedTimezone = tz);
    _updateClock();
  }

  Widget _buildClockWidget({required bool isCompact}) {
    return GestureDetector(
      onTap: _showTimezoneBottomSheet,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF131929),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2D48), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _clockDisplay,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (!isCompact)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _dateDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF4A6080),
                                fontSize: 9,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _selectedTimezone.label,
                              style: const TextStyle(
                                color: Color(0xFF9D97FF),
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF4A6080),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showTimezoneBottomSheet() {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = min(screenHeight * 0.75, 520.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1520),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A5E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Pilih Zona Waktu',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _timezones.length,
                  itemBuilder: (_, index) {
                    final tz = _timezones[index];
                    final isSelected = tz.label == _selectedTimezone.label;
                    return ListTile(
                      dense: true,
                      onTap: () {
                        Navigator.pop(context);
                        _onTimezoneChanged(tz);
                      },
                      leading: Container(
                        width: 46,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6C63FF).withOpacity(0.2)
                              : const Color(0xFF131929),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6C63FF)
                                : const Color(0xFF1E2D48),
                          ),
                        ),
                        child: Text(
                          tz.label,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF9D97FF)
                                : const Color(0xFF4A6080),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Text(
                        tz.city,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFFB0BEC5),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        'UTC${tz.offsetHours >= 0 ? '+' : ''}${tz.offsetHours}'
                        '${tz.offsetMinutes > 0 ? ':${tz.offsetMinutes.toString().padLeft(2, '0')}' : ''}',
                        style: const TextStyle(
                          color: Color(0xFF2E4060),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF6C63FF),
                              size: 20,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),  
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 390;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F1A),
      appBar: AppBar(
      title: const Text('Jaga Lilin'),
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      backgroundColor: const Color(0xFF0C0F1A),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _buildClockWidget(isCompact: isCompact),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.currency_exchange),
          onPressed: () {},
        ),
      ],
    ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0C0F1A),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Market'),
          BottomNavigationBarItem(
            icon: Icon(Icons.videogame_asset),
            label: 'Game',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Lokasi'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color.fromARGB(255, 70, 34, 34),
        unselectedItemColor: const Color(0xFF4A6080),
        onTap: _onItemTapped,
      ),
    );
  }
}

// WIDGET KHUSUS PROFIL & SARAN TPM
class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage: NetworkImage(
            'https://via.placeholder.com/150',
          ), // Placeholder gambar profil
        ),
        SizedBox(height: 16),
        Center(
          child: Text(
            'User',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        Divider(),
        ListTile(
          leading: Icon(Icons.feedback),
          title: Text('Saran & Kesan Kuliah TPM'),
          subtitle: Text('Beri masukan untuk mata kuliah ini'),
          onTap: () {
            // TODO: Buka form saran
          },
        ),
        ListTile(
          leading: Icon(Icons.settings),
          title: Text('Setting'),
          subtitle: Text('Pengaturan aplikasi'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }
}
