import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../feature/settings_screen.dart';
// import '../feature/gamescreen.dart';
import '../feature/qr_scanner_screen.dart';

class ProfileMenu extends StatefulWidget {
  const ProfileMenu({super.key});

  @override
  State<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends State<ProfileMenu> {
  String _userName = 'User';
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString('full_name') ?? '';
    final username = prefs.getString('username') ?? '';

    String currentUsername = 'User';
    if (fullName.isNotEmpty) {
      currentUsername = fullName;
    } else if (username.isNotEmpty) {
      currentUsername = username;
    }

    final savedUsername = username.isNotEmpty ? username : currentUsername;
    final imagePath = prefs.getString('profile_image_path_$savedUsername');

    setState(() {
      _userName = currentUsername;
      _imagePath = imagePath;
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? '';
      final fullName = prefs.getString('full_name') ?? '';
      final savedUsername = username.isNotEmpty
          ? username
          : (fullName.isNotEmpty ? fullName : 'User');

      setState(() {
        _imagePath = pickedFile.path;
      });

      await prefs.setString(
        'profile_image_path_$savedUsername',
        pickedFile.path,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white24,
                  backgroundImage: _imagePath != null && _imagePath!.isNotEmpty
                      ? FileImage(File(_imagePath!)) as ImageProvider
                      : const NetworkImage('https://via.placeholder.com/150'),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6C63FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _userName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 32),
          ListTile(
            leading: const Icon(Icons.feedback, color: Colors.white),
            title: const Text(
              'Saran & Kesan Kuliah TPM',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Beri masukan untuk mata kuliah ini',
              style: TextStyle(color: Colors.white70),
            ),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(
              Icons.qr_code_scanner,
              color: Color(0xFF638BFF),
            ),
            title: const Text('Scan QR Code'),
            subtitle: const Text(
              'Pindai kode QR dan simpan',
              style: TextStyle(color: Color(0xFF8B9BB4), fontSize: 12),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const QRScannerScreen(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white),
            title: const Text('Setting', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Pengaturan aplikasi',
              style: TextStyle(color: Colors.white70),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
