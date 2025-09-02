// lib/muteahhit/contractor_project_detail_page.dart
import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';

// 🔽 MÜTEAHHİT modüllerine yönlendiriyoruz (salt-okuma)
import 'package:santiyemfinal/muteahhit/contractor_stok_takip_page.dart';
import 'package:santiyemfinal/muteahhit/contractor_media_arsiv_page.dart';
import 'package:santiyemfinal/muteahhit/contractor_raporlar_page.dart';
import 'package:santiyemfinal/muteahhit/contractor_personel_takip_page.dart';
import 'package:santiyemfinal/muteahhit/contractor_metraj_hesap_page.dart';

class ContractorProjectDetailPage extends StatefulWidget {
  final Map<String, dynamic> project; // şef tarafındaki satırın aynısı
  const ContractorProjectDetailPage({super.key, required this.project});

  @override
  State<ContractorProjectDetailPage> createState() =>
      _ContractorProjectDetailPageState();
}

class _ContractorProjectDetailPageState
    extends State<ContractorProjectDetailPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;
  late final String _projectName;

  double _projectProgressRatio = 0.0; // 0..1
  List<Map<String, dynamic>> _buildings = [];
  final Map<String, double> _buildingProgressRatio = {}; // id -> 0..1

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _projectName = (widget.project['name'] ?? 'Proje').toString();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      // 1) Proje ilerlemesi
      try {
        final row = await supabase
            .from('project_progress')
            .select('progress_ratio')
            .eq('project_id', _projectId)
            .maybeSingle();

        _projectProgressRatio =
            (row?['progress_ratio'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {
        _projectProgressRatio = 0.0;
      }

      // 2) Yapılar
      try {
        final b = await supabase
            .from('project_buildings')
            .select('id,name,description,floors,floor_area_m2,created_at')
            .eq('project_id', _projectId)
            .order('created_at');
        _buildings = List<Map<String, dynamic>>.from(b as List);
      } catch (_) {
        _buildings = [];
      }

      // 3) Yapı ilerlemeleri
      _buildingProgressRatio.clear();
      try {
        final bp = await supabase
            .from('building_progress')
            .select('building_id,progress_ratio')
            .eq('project_id', _projectId);

        for (final r in (bp as List)) {
          final id = (r['building_id'] ?? '').toString();
          _buildingProgressRatio[id] =
              (r['progress_ratio'] as num?)?.toDouble() ?? 0.0;
        }
      } catch (_) {
        // boş bırak
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = 'Veriler alınamadı: $e';
        _loading = false;
      });
    }
  }

  // --- Yapılar bölümü (salt-okuma) ---
  Widget _buildBuildings() {
    if (_buildings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Yapılar / Bloklar',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._buildings.map((b) {
          final id = (b['id'] ?? '').toString();
          final name = (b['name'] ?? 'Yapı').toString();
          final desc = (b['description'] ?? '').toString();
          final floors = (b['floors'] ?? 0).toString();
          final ratio = (_buildingProgressRatio[id] ?? 0.0).clamp(0.0, 1.0);
          final pct = (ratio * 100).toStringAsFixed(0);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.apartment),
                    title: Text(name),
                    subtitle: Text([
                      if (desc.isNotEmpty) desc,
                      'Kat Sayısı: $floors',
                    ].join(' • ')),
                    trailing: Text('%$pct',
                        style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    color: Colors.teal,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final projectPct = (_projectProgressRatio * 100.0).clamp(0.0, 100.0);

    return Scaffold(
      appBar: AppBar(title: Text('Proje Detayı — $_projectName')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!))
          : RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Proje Adı: ${project['name']}",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text("İl: ${project['il']} / İlçe: ${project['ilce']}"),
              Text("Ada: ${project['ada']} / Parsel: ${project['parsel']}"),
              const SizedBox(height: 16),

              const Text("İnşaat Tamamlanma (Ağırlıklı)",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140, height: 140,
                      child: CircularProgressIndicator(
                        strokeWidth: 12,
                        value: _projectProgressRatio,
                        color: Colors.teal,
                        backgroundColor: Colors.grey.shade300,
                      ),
                    ),
                    Text("%${projectPct.toStringAsFixed(0)}",
                        style: const TextStyle(fontSize: 20)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildBuildings(),
              const SizedBox(height: 24),

              // DWG listesi burada yok → Metraj ekranında
              ElevatedButton.icon(
                icon: const Icon(Icons.rule),
                label: const Text("Metraj Hesabı (DWG)"),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContractorMetrajHesapPage(project: project),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Diğer modüller: salt-okuma takip (müteahhit tarafı)
              ElevatedButton.icon(
                icon: const Icon(Icons.warehouse),
                label: const Text("Stok Takip"),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContractorStokTakipPage(project: project),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text("Fotoğraf / Video Arşivi"),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContractorMediaArsivPage(project: project),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Şantiye Raporları"),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContractorRaporlarPage(project: project),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.group),
                label: const Text("Personel ve Ücret Takibi"),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContractorPersonelTakipPage(project: project),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
