// lib/muteahhit/contractor_projects_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'contractor_project_detail_page.dart';

class ContractorProjectsPage extends StatefulWidget {
  final String contractorUid;   // header’da göstermek için
  final String contractorEmail; // header’da göstermek için
  const ContractorProjectsPage({
    super.key,
    required this.contractorUid,
    required this.contractorEmail,
  });

  @override
  State<ContractorProjectsPage> createState() => _ContractorProjectsPageState();
}

class _ContractorProjectsPageState extends State<ContractorProjectsPage> {
  Future<List<Map<String, dynamic>>>? _future;
  final _foremanCtrl = TextEditingController();
  final _projectCtrl = TextEditingController();

  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _future = _fetchProjects();
  }

  @override
  void dispose() {
    _foremanCtrl.dispose();
    _projectCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _fetchProjects());
  }

  // --- Yardımcı: Supabase in() için id'leri güvenli parçalara böl (50’lik chunk’lar).
  Future<List<Map<String, dynamic>>> _fetchProjectsFromSupabase(List<String> ids) async {
    final result = <Map<String, dynamic>>[];
    const chunkSize = 50;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, (i + chunkSize > ids.length) ? ids.length : i + chunkSize);
      debugPrint('🧭 [CTR-LIST] Supabase in() chunk ${i ~/ chunkSize + 1} / ${(ids.length / chunkSize).ceil()} → ${chunk.length} id');
      final rows = await supabase
          .from('projects')
          .select('id,name,il,ilce,ada,parsel,foreman_id,created_at')
          .in_('id', chunk)
          .order('created_at', ascending: false);
      result.addAll(List<Map<String, dynamic>>.from(rows as List));
    }
    return result;
  }

  /// Firestore’daki linked_projects’e göre Supabase’ten proje satırlarını getirir.
  Future<List<Map<String, dynamic>>> _fetchProjects() async {
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null) {
        debugPrint('❌ [CTR-LIST] currentUser=null');
        return [];
      }
      // Firestore kuralı gereği: yalnızca kendi ağacına erişebilir.
      if (current.uid != widget.contractorUid) {
        debugPrint('❌ [CTR-LIST] UID mismatch: auth=${current.uid} vs param=${widget.contractorUid}');
        return [];
      }

      debugPrint('🧭 [CTR-LIST] Firestore linked_projects okunuyor… uid=${current.uid}');
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(current.uid)
          .collection('linked_projects')
          .orderBy('createdAt', descending: true)
          .get();

      final ids = snap.docs.map((d) => d.id).toList(); // docId = project_id
      debugPrint('🧭 [CTR-LIST] linked count=${ids.length} ids=$ids');

      if (ids.isEmpty) return [];

      final list = await _fetchProjectsFromSupabase(ids);
      debugPrint('🧭 [CTR-LIST] Supabase OK: ${list.length} proje');
      return list;
    } catch (e) {
      debugPrint('❌ [CTR-LIST] Listeleme hatası: $e');
      return [];
    }
  }

  void _openAddDialog() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Yeni Proje Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _foremanCtrl,
              decoration: const InputDecoration(
                labelText: 'Şantiye Şefi UID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _projectCtrl,
              decoration: const InputDecoration(
                labelText: 'Proje ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _adding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link),
                label: const Text('Ekle'),
                onPressed: _adding ? null : _addProjectLink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Şef UID + Proje ID doğrular → Firestore’a kaydeder (doc id = project_id)
  Future<void> _addProjectLink() async {
    final foremanId = _foremanCtrl.text.trim();
    final projectId  = _projectCtrl.text.trim();

    if (foremanId.isEmpty || projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şantiye Şefi UID ve Proje ID gerekli.')),
      );
      return;
    }

    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum bulunamadı.')),
      );
      return;
    }
    // Firestore Rules: sadece /users/{auth.uid}/… yazabilir.
    if (current.uid != widget.contractorUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yetkisiz işlem (UID uyuşmuyor).')),
      );
      return;
    }

    setState(() => _adding = true);
    try {
      debugPrint('🧭 [CTR-ADD] Doğrulama: projects(id=$projectId, foreman_id=$foremanId)…');
      final p = await supabase
          .from('projects')
          .select('id, name, foreman_id')
          .eq('id', projectId)
          .eq('foreman_id', foremanId)
          .maybeSingle();

      if (p == null) {
        debugPrint('⚠️ [CTR-ADD] Proje bulunamadı veya şef eşleşmiyor.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proje bulunamadı veya şef ile eşleşmiyor.')),
          );
        }
        return;
      }
      debugPrint('🧭 [CTR-ADD] Doğrulama OK: ${p['name']}');

      // Firestore’a idempotent kaydet (doc id = projectId)
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(current.uid) // 🔒 sadece kendi ağacı
          .collection('linked_projects')
          .doc(projectId);

      final exists = (await docRef.get()).exists;
      if (exists) {
        debugPrint('ℹ️ [CTR-ADD] Zaten listede. (dokunma)');
      }

      await docRef.set({
        'project_id': projectId,
        'foreman_id': foremanId,
        'addedBy': widget.contractorEmail,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context); // bottom sheet
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proje “Projelerim” listesine eklendi.')),
      );
      _foremanCtrl.clear();
      _projectCtrl.clear();
      _reload();
    } catch (e) {
      debugPrint('❌ [CTR-ADD] Ekleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekleme hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final info = 'UID: ${widget.contractorUid} • ${widget.contractorEmail}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Müteahhit – Projelerim'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(info, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Proje Ekle'),
      ),
      body: user == null
          ? const Center(child: Text('Oturum bulunamadı.'))
          : FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snap.data ?? [];
          if (projects.isEmpty) {
            return const Center(child: Text('Projeler boş. “Yeni Proje Ekle” ile ekleyin.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: projects.length,
            itemBuilder: (_, i) {
              final p = projects[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.apartment, color: Colors.teal),
                  title: Text(p['name'] ?? 'Proje'),
                  subtitle: Text('${p['il'] ?? ''} / ${p['ilce'] ?? ''}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContractorProjectDetailPage(project: p),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      try {
                        debugPrint('🧭 [CTR-DEL] Listeden kaldırılıyor: ${p['id']}');
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.contractorUid) // 🔒 sadece kendi ağacı
                            .collection('linked_projects')
                            .doc(p['id'] as String)
                            .delete();
                        _reload();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Listeden kaldırıldı.')),
                        );
                      } catch (e) {
                        debugPrint('❌ [CTR-DEL] Hata: $e');
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Silme hatası: $e')),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
