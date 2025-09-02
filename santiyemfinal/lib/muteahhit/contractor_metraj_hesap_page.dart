import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:url_launcher/url_launcher.dart';

class ContractorMetrajHesapPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const ContractorMetrajHesapPage({super.key, required this.project});

  @override
  State<ContractorMetrajHesapPage> createState() => _ContractorMetrajHesapPageState();
}

class _ContractorMetrajHesapPageState extends State<ContractorMetrajHesapPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;
  late final String _projectName;

  List<Map<String, dynamic>> _dwgFiles = [];

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _projectName = (widget.project['name'] ?? '').toString();
    _loadDwg();
  }

  Future<void> _loadDwg() async {
    setState(() { _loading = true; _err = null; });
    try {
      final rows = await supabase
          .from('project_dwg_files')
          .select('id,filename,file_url,storage_path,status,created_at')
          .eq('project_id', _projectId)
          .order('created_at', ascending: false);

      _dwgFiles = List<Map<String, dynamic>>.from(rows as List);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = 'DWG dosyaları alınamadı: $e'; _loading = false; });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geçersiz URL.')));
    }
  }

  Widget _item(Map<String, dynamic> r) {
    final file = (r['filename'] ?? 'dosya.dwg').toString();
    final url = (r['file_url'] ?? '').toString();
    final status = (r['status'] ?? 'pending').toString();

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
                  child: Text(file, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
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
      appBar: AppBar(title: Text('Metraj — $_projectName')),
      // 👇 MÜTEAHHİTTE YÜKLEME/SİPARİŞ YOK → FAB YOK, METRAJ OLUŞTURMA YOK
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
