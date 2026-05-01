import 'dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'settings_screen.dart';

import 'map_screen.dart';
import 'gamescreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Daftar halaman untuk Bottom Navigation
  static final List<Widget> _widgetOptions = <Widget>[
    DashboardScreen(),
    AtmFinderScreen(),
    ProfileMenu(), // Menu Profil & Saran Kesan (Wajib Tugas Akhir)
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jaga Lilin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.currency_exchange),
            onPressed: () {
              // TODO: Navigasi ke Konverter Mata Uang
            },
          ),
        ],
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Market'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Lokasi'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
        currentIndex: _selectedIndex,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        const CircleAvatar(
          radius: 50,
          backgroundColor: Color(0xFF283548),
          backgroundImage: NetworkImage(
            'https://via.placeholder.com/150',
          ), // Placeholder gambar profil
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'User',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.feedback, color: Color(0xFF638BFF)),
                title: const Text('Saran & Kesan Kuliah TPM'),
                subtitle: const Text('Beri masukan untuk mata kuliah ini', style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 12)),
                onTap: () {
                  // TODO: Buka form saran
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.videogame_asset, color: Color(0xFF638BFF)),
                title: const Text('Mini Game: Crypto Flip'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GameScreen()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings, color: Color(0xFF638BFF)),
                title: const Text('Setting'),
                subtitle: const Text('Pengaturan aplikasi', style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 12)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
