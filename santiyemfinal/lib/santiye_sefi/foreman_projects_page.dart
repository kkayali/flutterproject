import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:santiyemfinal/santiye_sefi//project_detail_page.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:uuid/uuid.dart';

class ForemanProjectsPage extends StatefulWidget {
  const ForemanProjectsPage({super.key});

  @override
  State<ForemanProjectsPage> createState() => _ForemanProjectsPageState();
}

class _ForemanProjectsPageState extends State<ForemanProjectsPage> {
  // ---------- Form controller’ları
  final nameController = TextEditingController();
  final adaController = TextEditingController();
  final parselController = TextEditingController();

  // ---------- İl/İlçe
  bool isJsonLoaded = false;
  List<String> iller = [];
  Map<String, List<String>> ilcelerMap = {};
  String? selectedIl;
  String? selectedIlce;

  // ---------- Yapı/Blok dinamik formu
  final _buildingCountCtrl = TextEditingController(text: '1');
  List<_BuildingInput> buildings = [ _BuildingInput() ];

  // ---------- UI state
  bool isUploading = false;

  // ---------- Listeyi gerçekten yenilemek için future’ı state’te tutuyoruz
  Future<List<Map<String, dynamic>>>? _projectsFuture;

  @override
  void initState() {
    super.initState();
    loadIlIlceJson();
    _refreshProjects();
  }

  @override
  void dispose() {
    nameController.dispose();
    adaController.dispose();
    parselController.dispose();
    _buildingCountCtrl.dispose();
    for (final b in buildings) { b.dispose(); }
    super.dispose();
  }

  // ==========================================================
  // DATA
  // ==========================================================
  Future<void> loadIlIlceJson() async {
    final jsonString = await rootBundle.loadString('lib/data/Turkey.json');
    final List data = json.decode(jsonString);
    for (var il in data) {
      final String ilAdi = il['name'];
      final List<String> ilceler = List<String>.from(il['districts'].map((e) => e['name']));
      iller.add(ilAdi);
      ilcelerMap[ilAdi] = ilceler;
    }
    setState(() => isJsonLoaded = true);
  }

  void _refreshProjects() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _projectsFuture = getProjects(uid);
    });
  }

  Future<List<Map<String, dynamic>>> getProjects(String uid) async {
    try {
      final rows = await supabase
          .from('projects')
          .select('id, name, il, ilce, ada, parsel, dwg_urls, created_at')
          .eq('foreman_id', uid)
          .order('created_at', ascending: false);

      // ID’ye göre tekilleştir (ileride join’ler eklenirse çoğalma olmasın)
      final Map<String, Map<String, dynamic>> byId = {};
      for (final r in rows) {
        final id = (r['id'] ?? '').toString();
        if (id.isEmpty) continue;
        byId[id] = Map<String, dynamic>.from(r);
      }
      final list = byId.values.toList();
      debugPrint("✅ getProjects (uniq): ${list.length} proje");
      return list;
    } catch (e) {
      debugPrint("❌ getProjects hata: $e");
      return [];
    }
  }

  // ==========================================================
  // STORAGE yardımcıları (silme için tutuyoruz)
  // ==========================================================
  Future<void> _deleteFolder(String prefix) async {
    try {
      final items = await supabase.storage.from('projectfiles').list(path: prefix);
      for (final obj in items) {
        final fullPath = '$prefix/${obj.name}';
        await supabase.storage.from('projectfiles').remove([fullPath]);
      }
    } catch (e) {
      // klasör yoksa/erişim yoksa sessizce geç
      debugPrint("ℹ️ Storage temizliği ($prefix) es geçti: $e");
    }
  }

  // ==========================================================
  // PROJE EKLE  (DWG ZORUNLU DEĞİL)
  // ==========================================================
  Future<void> uploadProject() async {
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;

    if (firebaseUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Oturum bulunamadı.")));
      return;
    }
    if (selectedIl == null || selectedIlce == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İl/İlçe seçiniz.")));
      return;
    }
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proje ismini giriniz.")));
      return;
    }
    for (final b in buildings) {
      final floors = int.tryParse(b.floors.text.trim()) ?? 0;
      if (b.name.text.trim().isEmpty || floors < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Yapı bilgilerini eksiksiz giriniz.")));
        return;
      }
    }

    setState(() => isUploading = true);

    final projectId = const Uuid().v4();

    try {
      // 1) projects insert (DWG alanı boş liste)
      await supabase.from('projects').insert({
        'id': projectId,
        'foreman_id': firebaseUid,
        'name': nameController.text.trim(),
        'il': selectedIl,
        'ilce': selectedIlce,
        'ada': adaController.text.trim(),
        'parsel': parselController.text.trim(),
        'dwg_urls': [], // 👈 DWG artık istenmiyor
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2) project_buildings insert (bağımsız try)
      final buildingRows = buildings.map((b) => {
        'project_id': projectId,
        'name': b.name.text.trim(),
        'description': b.desc.text.trim(),
        'floors': int.tryParse(b.floors.text.trim()) ?? 0,
        'floor_area_m2': double.tryParse(b.floorArea.text.trim()) ?? 0,
      }).toList();

      if (buildingRows.isNotEmpty) {
        try {
          await supabase.from('project_buildings').insert(buildingRows);
        } catch (e) {
          debugPrint("⚠️ project_buildings insert hatası: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Proje kaydedildi ancak yapılar listeye eklenemedi.")),
            );
          }
        }
      }

      // Başarılı → modal’ı kapat, formları temizle ve listeyi yenile
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proje başarıyla eklendi.")));

      nameController.clear();
      adaController.clear();
      parselController.clear();

      final oldBuildings = List<_BuildingInput>.from(buildings);
      setState(() {
        selectedIl = null;
        selectedIlce = null;
        buildings = [ _BuildingInput() ];
        _buildingCountCtrl.text = '1';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final b in oldBuildings) { b.dispose(); }
      });

      _refreshProjects();
    } catch (e) {
      debugPrint("❌ Proje kayıt hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Kayıt hatası: $e")));
      }
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  // ==========================================================
  // PROJE SİL (RPC + Cascade + Storage temizliği)
  // ==========================================================
  Future<void> deleteProject(String projectId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception("Oturum bulunamadı (uid=null).");
      }

      await _deleteFolderRecursive('dwg/$projectId');
      await _deleteFolderRecursive('reports/$projectId');
      await _deleteFolderRecursive('media/$projectId');

      final rpcRes = await supabase.rpc(
        'delete_project_cascade',
        params: {
          'p_project_id': projectId,
          'p_uid': uid,
        },
      );
      debugPrint("✅ RPC delete_project_cascade response: $rpcRes");

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Proje silindi.")),
      );

      _refreshProjects();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Silme hatası: $e")),
        );
      }
      debugPrint("❌ Proje silme hatası: $e");
    }
  }

  // ==========================================================
  // STORAGE: recursive silme + retry
  // ==========================================================
  Future<void> _deleteFolderRecursive(String prefix) async {
    try {
      final items = await supabase.storage.from('projectfiles').list(path: prefix);

      if (items.isEmpty) {
        debugPrint("ℹ️ Storage boş ($prefix)");
        return;
      }

      const batchSize = 50;
      for (var i = 0; i < items.length; i += batchSize) {
        final batch = items.sublist(i, (i + batchSize > items.length) ? items.length : i + batchSize);
        final paths = batch.map((e) => '$prefix/${e.name}').toList();
        await _removeWithRetry(paths);
      }
    } catch (e) {
      debugPrint("ℹ️ Storage temizliği ($prefix) es geçti: $e");
    }
  }

  Future<void> _removeWithRetry(List<String> paths, {int maxRetries = 3}) async {
    int attempt = 0;
    while (true) {
      try {
        await supabase.storage.from('projectfiles').remove(paths);
        return;
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) rethrow;
        debugPrint("⚠️ remove retry ($attempt): $e");
        await Future.delayed(Duration(milliseconds: 400 * attempt * attempt));
      }
    }
  }

  // ==========================================================
  // UI
  // ==========================================================
  void showNewProjectForm() {
    if (!isJsonLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İl/İlçe verileri yükleniyor...")));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Yeni Proje Ekle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Proje İsmi')),
              const SizedBox(height: 12),

              // İl / İlçe
              DropdownButtonFormField<String>(
                value: selectedIl,
                decoration: const InputDecoration(labelText: 'İl Seç', border: OutlineInputBorder()),
                items: iller.map((il) => DropdownMenuItem(value: il, child: Text(il))).toList(),
                onChanged: (val) => setState(() {
                  selectedIl = val;
                  selectedIlce = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedIlce,
                decoration: const InputDecoration(labelText: 'İlçe Seç', border: OutlineInputBorder()),
                items: selectedIl != null
                    ? ilcelerMap[selectedIl]!.map((ilce) => DropdownMenuItem(value: ilce, child: Text(ilce))).toList()
                    : [],
                onChanged: (val) => setState(() => selectedIlce = val),
              ),
              const SizedBox(height: 12),

              // Ada / Parsel
              TextField(controller: adaController, keyboardType: TextInputType.text, decoration: const InputDecoration(labelText: 'Ada No', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: parselController, keyboardType: TextInputType.text, decoration: const InputDecoration(labelText: 'Parsel No', border: OutlineInputBorder())),
              const SizedBox(height: 16),

              // Yapı / Blok
              const Text('Yapı / Blok Bilgileri', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _buildingCountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Yapı Sayısı', border: OutlineInputBorder()),
                onChanged: (v) {
                  final count = int.tryParse(v) ?? 1;
                  setState(() {
                    if (count < 1) {
                      buildings = [ _BuildingInput() ];
                      _buildingCountCtrl.text = '1';
                    } else if (count > buildings.length) {
                      while (buildings.length < count) { buildings.add(_BuildingInput()); }
                    } else if (count < buildings.length) {
                      final removed = buildings.sublist(count);
                      buildings = buildings.sublist(0, count);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        for (final r in removed) { r.dispose(); }
                      });
                    }
                  });
                },
              ),
              const SizedBox(height: 8),

              ...List.generate(buildings.length, (i) {
                final b = buildings[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Yapı ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(controller: b.name, decoration: const InputDecoration(labelText: 'Yapı Adı', border: OutlineInputBorder())),
                        const SizedBox(height: 8),
                        TextField(controller: b.desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Açıklama', border: OutlineInputBorder())),
                        const SizedBox(height: 8),
                        TextField(controller: b.floors, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kat Sayısı', border: OutlineInputBorder())),
                        const SizedBox(height: 8),
                        TextField(controller: b.floorArea, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Yapı m²', border: OutlineInputBorder())),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: isUploading ? null : uploadProject,
                icon: isUploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text("Projeyi Kaydet"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projelerim'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: uid == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: showNewProjectForm,
              icon: const Icon(Icons.add),
              label: const Text("Yeni Proje Ekle"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _projectsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return const Center(child: Text("Proje verileri alınamadı."));
                  }

                  final projects = snapshot.data ?? [];
                  if (projects.isEmpty) {
                    return const Center(child: Text("Henüz proje eklenmemiş."));
                  }

                  return ListView.builder(
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final data = projects[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.folder, color: Colors.teal),
                          title: Text(data['name'] ?? 'Proje'),
                          subtitle: Text('${data['il'] ?? ''} / ${data['ilce'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("Proje Sil"),
                                  content: const Text("Bu projeyi silmek istediğinize emin misiniz?"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal")),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Sil", style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await deleteProject(data['id'] as String);
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ProjectDetailPage(project: data)),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// Yardımcı sınıf
// ----------------------------------------------------------
class _BuildingInput {
  final TextEditingController name = TextEditingController();
  final TextEditingController desc = TextEditingController();
  final TextEditingController floors = TextEditingController(text: '0');
  final TextEditingController floorArea = TextEditingController(text: '0');

  void dispose() {
    name.dispose();
    desc.dispose();
    floors.dispose();
    floorArea.dispose();
  }
}
