import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'foreman_projects_page.dart';

class ForemanPanel extends StatefulWidget {
  const ForemanPanel({super.key});

  @override
  State<ForemanPanel> createState() => _ForemanPanelState();
}

class _ForemanPanelState extends State<ForemanPanel> {
  String? fullName;
  String? foremanId;

  @override
  void initState() {
    super.initState();
    loadUserInfo();
  }

  Future<void> loadUserInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = snapshot.data();
      if (data != null) {
        setState(() {
          fullName = data['name'] ?? 'Şantiye Şefi';
          foremanId = uid;
        });
      }
    } catch (e) {
      debugPrint("Kullanıcı bilgisi alınamadı: $e");
    }
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Şantiye Şefi Paneli'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ayarlar',
            onPressed: () {
              // TODO: Ayarlar ekranı eklenecek
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: signOut,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              'Hoş geldiniz, ${fullName ?? '...'}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Şantiye Şefi ID: ${foremanId ?? "Bilinmiyor"}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Colors.teal),
                    tooltip: 'Kopyala',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: foremanId ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ID kopyalandı')),
                      );
                    },
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Devam Eden Projelerim',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: uid == null
                  ? const Center(child: Text("Kullanıcı giriş yapmamış."))
                  : FutureBuilder<List<Map<String, dynamic>>>(
                future: supabase
                    .from('projects')
                    .select()
                    .eq('foreman_id', uid)
                    .then((value) => value as List<Map<String, dynamic>>),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return const Center(child: Text("Veriler alınamadı."));
                  }

                  final projects = snapshot.data ?? [];
                  if (projects.isEmpty) {
                    return const Center(child: Text("Devam eden proje yok."));
                  }

                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      final name = project['name'] ?? 'Proje';
                      final rawProgress = project['progress'];
                      final progress = rawProgress is num ? rawProgress.toDouble() : 0.0;

                      return Container(
                        width: 220,
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4)
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progress / 100,
                              minHeight: 10,
                              backgroundColor: Colors.grey.shade300,
                              color: Colors.teal,
                            ),
                            const SizedBox(height: 4),
                            Text('%${progress.toStringAsFixed(1)} tamamlandı'),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ForemanProjectsPage()),
                );
              },
              icon: const Icon(Icons.folder),
              label: const Text('Projelerim'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
