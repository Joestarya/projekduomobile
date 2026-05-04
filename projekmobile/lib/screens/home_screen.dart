import 'package:flutter/material.dart';
import 'feature/dashboard/dashboard_screen.dart';
import 'feature/map/map_screen.dart';
import 'feature/user/profile_screen.dart';
import 'feature/game/gamescreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // IndexedStack butuh list yang dibuat sekali — jangan pindah ke dalam build()
  static final List<Widget> _widgetOptions = <Widget>[
    DashboardScreen(),
    AtmFinderScreen(),
    const GameScreen(),
    ProfileMenu(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: semua screen tetap mount di background.
      // GameScreen timer tidak akan cancel saat user pindah tab.
      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0C0F1A),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Market'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Lokasi'),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_esports),
            label: 'Game',
          ),
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
