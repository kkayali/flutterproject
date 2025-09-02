import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:url_launcher/url_launcher.dart';

class RaporlarPage extends StatefulWidget {
  final Map<String, dynamic> project;

  const RaporlarPage({super.key, required this.project});

  @override
  State<RaporlarPage> createState() => _RaporlarPageState();
}

class _RaporlarPageState extends State<RaporlarPage> {
  final List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  bool _busy = false;

  static const _reportTypes = XTypeGroup(
    label: 'Doküman',
    extensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
  );

  String get _projectId => (widget.project['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('project_reports')
          .select()
          .eq('project_id', _projectId)
          .order('created_at', ascending: false);

      setState(() {
        _reports
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(data));
      });
    } catch (e) {
      debugPrint('❌ Raporlar çekilemedi: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raporlar alınamadı')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
  }

  Future<void> _addReportDialog() async {
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    XFile? pickedFile;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 8,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Yeni Rapor Ekle',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Rapor Başlığı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final file = await openFile(acceptedTypeGroups: [_reportTypes]);
                              if (file != null) {
                                setLocal(() => pickedFile = file);
                              }
                            },
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              pickedFile == null ? 'Dosya Seç' : pickedFile!.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                          if (titleCtrl.text.trim().isEmpty || pickedFile == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Başlık ve dosya zorunludur.')),
                            );
                            return;
                          }
                          await _createAndUploadReport(
                            title: titleCtrl.text.trim(),
                            note: noteCtrl.text.trim(),
                            file: pickedFile!,
                          );
                          if (mounted) Navigator.pop(ctx);
                        },
                        icon: _busy
                            ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_upload),
                        label: const Text('Yükle ve Kaydet'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _createAndUploadReport({
    required String title,
    required String note,
    required XFile file,
  }) async {
    setState(() => _busy = true);
    try {
      // 1) Dosyayı oku
      final Uint8List bytes = await file.readAsBytes();
      final safeName = _sanitizeFilename(file.name);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'reports/$_projectId/${stamp}_$safeName';

      // 2) Storage’a yükle
      await supabase.storage.from('projectfiles').uploadBinary(
        storagePath,
        bytes,
      );

      // 3) Public URL al
      final String publicUrl =
      supabase.storage.from('projectfiles').getPublicUrl(storagePath);

      // 4) DB’ye yaz
      final inserted = await supabase.from('project_reports').insert({
        'project_id': _projectId,
        'title': title,
        'note': note,
        'filename': safeName,
        'file_url': publicUrl,
        'storage_path': storagePath,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      // 5) Listeyi güncelle
      setState(() {
        _reports.insert(0, Map<String, dynamic>.from(inserted));
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rapor yüklendi ve kaydedildi.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Yükleme/Kaydetme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReport(Map<String, dynamic> item) async {
    final String url = (item['file_url'] ?? '') as String;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya URL bulunamadı.')),
      );
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _editReport(Map<String, dynamic> item) async {
    final titleCtrl = TextEditingController(text: (item['title'] ?? '').toString());
    final noteCtrl = TextEditingController(text: (item['note'] ?? '').toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raporu Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('İptal'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            child: const Text('Kaydet'),
            onPressed: () async {
              try {
                final updated = await supabase
                    .from('project_reports')
                    .update({
                  'title': titleCtrl.text.trim(),
                  'note': noteCtrl.text.trim(),
                })
                    .eq('id', item['id'])
                    .select()
                    .single();

                final idx = _reports.indexWhere((r) => r['id'] == item['id']);
                if (idx != -1) {
                  setState(() {
                    _reports[idx] = Map<String, dynamic>.from(updated);
                  });
                }
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                debugPrint('❌ Düzenleme hatası: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Hata: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReport(Map<String, dynamic> item) async {
    final String storagePath = (item['storage_path'] ?? '') as String;
    final dynamic id = item['id'];

    setState(() => _busy = true);
    try {
      if (storagePath.isNotEmpty) {
        await supabase.storage.from('projectfiles').remove([storagePath]);
      }
      await supabase.from('project_reports').delete().eq('id', id);

      setState(() {
        _reports.removeWhere((e) => e['id'] == id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rapor silindi.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Silme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectName = (widget.project['name'] ?? 'Proje').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('Şantiye Raporları - $projectName'),
        actions: [
          IconButton(
            onPressed: _addReportDialog,
            icon: const Icon(Icons.add),
            tooltip: 'Yeni Rapor',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
          ? const Center(child: Text('Henüz rapor eklenmemiş. Sağ üstten ekleyin.'))
          : RefreshIndicator(
        onRefresh: _fetchReports,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final item = _reports[index];

            // created_at string/DateTime olabilir → güvenli formatla
            DateTime createdAt;
            final raw = item['created_at'];
            if (raw is DateTime) {
              createdAt = raw;
            } else if (raw is String && raw.isNotEmpty) {
              createdAt = DateTime.tryParse(raw) ?? DateTime.now();
            } else {
              createdAt = DateTime.now();
            }

            final bool uploaded = ((item['file_url'] ?? '') as String).isNotEmpty;

            return Card(
              child: ListTile(
                leading: Icon(uploaded ? Icons.cloud_done : Icons.cloud_upload),
                title: Text((item['title'] ?? 'Rapor').toString()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (((item['note'] ?? '') as String).isNotEmpty)
                      Text((item['note'] ?? '').toString()),
                    Text(
                      '${(item['filename'] ?? '').toString()} • ${createdAt.toLocal()}'
                          .replaceAll('.000', ''),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (!uploaded)
                      const Text(
                        'Yükleme tamamlanmadı',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'open') _openReport(item);
                    if (val == 'edit') _editReport(item);
                    if (val == 'delete') _deleteReport(item);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'open',
                      child: ListTile(
                        leading: Icon(Icons.open_in_new),
                        title: Text('Aç / Görüntüle'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit),
                        title: Text('Düzenle'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Sil'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: _reports.length,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReportDialog,
        icon: const Icon(Icons.add),
        label: const Text('Rapor Ekle'),
      ),
    );
  }
}
