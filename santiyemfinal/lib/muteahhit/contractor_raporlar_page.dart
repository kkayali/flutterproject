import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:url_launcher/url_launcher.dart';

class ContractorRaporlarPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const ContractorRaporlarPage({super.key, required this.project});

  @override
  State<ContractorRaporlarPage> createState() => _ContractorRaporlarPageState();
}

class _ContractorRaporlarPageState extends State<ContractorRaporlarPage> {
  final List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  String get _projectId => (widget.project['id'] ?? '').toString();
  String get _projectName => (widget.project['name'] ?? 'Proje').toString();

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _loading = true);
    try {
      debugPrint('🧭 [CTR-RPR] project_reports fetch… project_id=$_projectId');
      final data = await supabase
          .from('project_reports')
          .select('id,title,note,filename,file_url,storage_path,created_at')
          .eq('project_id', _projectId)
          .order('created_at', ascending: false);

      _reports
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(data as List));
      debugPrint('✅ [CTR-RPR] ${_reports.length} kayıt');
    } catch (e) {
      debugPrint('❌ [CTR-RPR] Listeleme hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raporlar alınamadı')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openReport(Map<String, dynamic> item) async {
    final url = (item['file_url'] ?? '').toString();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosya URL bulunamadı.')),
      );
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('❌ [CTR-RPR] Açma hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Açılamadı: $e')),
      );
    }
  }

  DateTime _parseCreatedAt(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw is String && raw.isNotEmpty) {
      return (DateTime.tryParse(raw) ?? DateTime.now()).toLocal();
    }
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Şantiye Raporları — $_projectName')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
          ? const Center(child: Text('Henüz rapor yok.'))
          : RefreshIndicator(
        onRefresh: _fetchReports,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = _reports[index];
            final createdAt = _parseCreatedAt(item['created_at']);
            final uploaded = ((item['file_url'] ?? '') as String).isNotEmpty;

            return Card(
              child: ListTile(
                onTap: () => _openReport(item),
                leading: Icon(uploaded ? Icons.cloud_done : Icons.cloud_off),
                title: Text((item['title'] ?? 'Rapor').toString()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (((item['note'] ?? '') as String).isNotEmpty)
                      Text((item['note'] ?? '').toString()),
                    Text(
                      '${(item['filename'] ?? '').toString()} • ${createdAt.toString().replaceAll('.000', '')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.open_in_new),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    );
  }
}
