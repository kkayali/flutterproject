import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'contractor_projects_page.dart';

class ContractorHomePage extends StatelessWidget {
  const ContractorHomePage({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    // Çıkış sonrası geri dön → login sayfasına yönlendirilebilir
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Müteahhit – Anasayfa'),
        actions: [
          IconButton(
            tooltip: 'Çıkış Yap',
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.folder_shared),
          label: const Text('Projelerim'),
          onPressed: user == null
              ? null
              : () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContractorProjectsPage(
                contractorUid: user.uid,
                contractorEmail: user.email ?? '',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
