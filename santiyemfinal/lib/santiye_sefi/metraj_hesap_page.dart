import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:url_launcher/url_launcher.dart';

class MetrajHesapPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const MetrajHesapPage({super.key, required this.project});

  @override
  State<MetrajHesapPage> createState() => _MetrajHesapPageState();
}

class _MetrajHesapPageState extends State<MetrajHesapPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;
  late final String _projectName;

  List<Map<String, dynamic>> _dwgFiles = [];

  // Bu ek: Hangi dosyada “Hesapla”ya basıldığını tutuyoruz (UI’de tik göstermek için)
  final Set<String> _orderedFilenames = <String>{};

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _projectName = (widget.project['name'] ?? '').toString();
    _loadDwg();
  }

  Future<void> _loadDwg() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final rows = await supabase
          .from('project_dwg_files')
          .select('id, filename, file_url, storage_path, status, created_at')
          .eq('project_id', _projectId)
          .order('created_at', ascending: false);

      _dwgFiles = List<Map<String, dynamic>>.from(rows as List);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _err = 'DWG dosyaları alınamadı: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUploadDwg() async {
    try {
      final XFile? x = await openFile(
        acceptedTypeGroups: const [XTypeGroup(label: 'DWG', extensions: ['dwg'])],
      );
      if (x == null) return;

      final Uint8List bytes = await x.readAsBytes();
      final fileName = x.name;

      final objectKey = 'dwg/$_projectId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Storage: projectfiles bucket (kaynak)
      await supabase.storage.from('projectfiles').uploadBinary(objectKey, bytes);

      final publicUrl = supabase.storage.from('projectfiles').getPublicUrl(objectKey);

      // DB kaydı
      await supabase.from('project_dwg_files').insert({
        'project_id': _projectId,
        'filename': fileName,
        'file_url': publicUrl,
        'storage_path': objectKey,
        'status': 'pending',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DWG yüklendi.')));
      await _loadDwg();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e')));
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // === METRAJ HESAPLA → siparisler bucket + siparisler tablosu ===
  Future<void> _createSiparis(Map<String, dynamic> row) async {
    try {
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      if (email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oturum e-postası bulunamadı.')),
        );
        return;
      }

      final filename = (row['filename'] ?? 'dosya.dwg').toString();
      final sourcePath = (row['storage_path'] ?? '').toString(); // projectfiles içi
      if (sourcePath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçersiz kaynak yolu.')),
        );
        return;
      }

      // 1) Kaynaktan indir
      final Uint8List bytes =
      await supabase.storage.from('projectfiles').download(sourcePath);

      // 2) Hedef yola yükle (siparisler bucket)
      final destPath =
          'incoming/$_projectId/${DateTime.now().millisecondsSinceEpoch}_$filename';
      await supabase.storage.from('siparisler').uploadBinary(destPath, bytes);

      // 3) Public/Signed URL
      String fileUrl = '';
      try {
        fileUrl = supabase.storage.from('siparisler').getPublicUrl(destPath);
      } catch (_) {
        try {
          fileUrl = await supabase.storage
              .from('siparisler')
              .createSignedUrl(destPath, 60 * 60 * 24);
        } catch (_) {}
      }

      // 4) Tabloya sipariş kaydı
      await supabase.from('siparisler').insert({
        'project_id': _projectId,
        'filename': filename,
        'storage_path': destPath,
        'file_url': fileUrl,
        'user_email': email,
        'status': 'new',
      });

      // 👉 UI: butonu “tik”e çevir
      _orderedFilenames.add(filename);
      if (mounted) setState(() {});

      // 👉 İstenen mesaj
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Siparişiniz oluşturuldu. Sonuç size $email üzerinden en kısa süre içinde gönderilecektir. Teşekkürler.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sipariş oluşturulamadı: $e')),
      );
    }
  }

  Widget _item(Map<String, dynamic> r) {
    final file = (r['filename'] ?? 'dosya.dwg').toString();
    final url = (r['file_url'] ?? '').toString();
    final status = (r['status'] ?? 'pending').toString();

    final ordered = _orderedFilenames.contains(file);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.insert_drive_file, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(status, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: url.isEmpty ? null : () => _openUrl(url),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Görüntüle / İndir'),
                  ),
                ),
                const SizedBox(width: 8),

                // 👉 Turuncu METRAJ Hesapla / Tik'e dönüşür
                Expanded(
                  child: ordered
                      ? ElevatedButton.icon(
                    onPressed: null, // pasif
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Gönderildi'),
                  )
                      : ElevatedButton.icon(
                    onPressed: () => _createSiparis(r),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.calculate),
                    label: const Text('METRAJ Hesapla'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Metraj Hesabı — $_projectName')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndUploadDwg,
        icon: const Icon(Icons.upload_file),
        label: const Text('DWG Yükle'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!))
          : RefreshIndicator(
        onRefresh: _loadDwg,
        child: _dwgFiles.isEmpty
            ? ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('Henüz DWG yok.')),
          ],
        )
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _dwgFiles.length,
          itemBuilder: (_, i) => _item(_dwgFiles[i]),
        ),
      ),
    );
  }
}
