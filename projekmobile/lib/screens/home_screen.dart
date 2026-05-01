import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'feature/map_screen.dart';
import 'user/profile_screen.dart';
import 'feature/gamescreen.dart';

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
    const GameScreen(),
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
      
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0C0F1A),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Market'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Lokasi'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'Game'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
        onTap: _onItemTapped,
      ),
    );
  }
}
