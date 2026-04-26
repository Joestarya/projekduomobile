import 'dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../login_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Daftar halaman untuk Bottom Navigation
  static final List<Widget> _widgetOptions = <Widget>[
    DashboardScreen(),
    Text('Dashboard Portofolio & DCA (Segera Hadir)', style: TextStyle(fontSize: 20)),
    Text('Peta ATM Kripto (LBS) (Segera Hadir)', style: TextStyle(fontSize: 20)),
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
        title: Text('CoinWise'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: Icon(Icons.currency_exchange),
            onPressed: () {
              // TODO: Navigasi ke Konverter Mata Uang
            },
          )
        ],
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Portofolio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Lokasi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.indigo,
        onTap: _onItemTapped,
      ),
    );
  }
}

// ==========================================
// WIDGET KHUSUS PROFIL & SARAN TPM
// ==========================================
class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

  Future<void> _logout(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token'); // Hapus session
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage: NetworkImage('https://via.placeholder.com/150'), // Placeholder gambar profil
        ),
        SizedBox(height: 16),
        Center(child: Text('User CoinWise', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
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
          leading: Icon(Icons.videogame_asset),
          title: Text('Mini Game: Crypto Flip'),
          onTap: () {
            // TODO: Buka mini game
          },
        ),
        ListTile(
          leading: Icon(Icons.logout, color: Colors.red),
          title: Text('Logout', style: TextStyle(color: Colors.red)),
          onTap: () => _logout(context),
        ),
      ],
    );
  }
}