import 'package:flutter/material.dart';
import 'admin_panel_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final String _adminPassword = "123"; // Güçlü admin şifresi

  void _checkPassword() {
    if (_passwordController.text == _adminPassword) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AdminPanelScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hatalı şifre, tekrar deneyin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Girişi'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Lütfen Admin Şifresini Girin',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Şifre',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkPassword,
              child: const Text('Giriş Yap'),
            ),
          ],
        ),
      ),
    );
  }
}
