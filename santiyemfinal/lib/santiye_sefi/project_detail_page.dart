import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:flutter/services.dart';

import 'stok_takip_page.dart';
import 'media_arsiv_page.dart';
import 'raporlar_page.dart';
import 'personel_takip_page.dart';
import 'metraj_hesap_page.dart';

/// UI etiketi -> DB enum değeri (build_stage)
const Map<String, String> kStageLabelToEnum = {
  'Kazı ve Zemin İşleri': 'kazi_ve_zemin_isleri',
  'Grobeton ve Temel Hazırlık': 'grobeton_ve_temel_hazirlik',
  'Temel Donatısı ve Beton': 'temel_donatisi_ve_beton',
  'Temel Yalıtımı (Membran)': 'temel_yalitimi_membran',
  'Bodrum Perde ve Döşemeler': 'bodrum_perde_ve_dosemeler',
  'Kat Kolonları': 'kat_kolonlari',
  'Kat Kirişleri': 'kat_kirisleri',
  'Kat Döşemeleri': 'kat_dosemeleri',
  'Merdiven ve Sahanlıklar': 'merdiven_ve_sahanliklar',
  'Duvar Örme (Tüm Katlar)': 'duvar_orme_tum_katlar',
  'Çatı Konstrüksiyon ve Kaplama': 'cati_konstruksiyon_ve_kaplama',
  'Dış Cephe Kaplaması': 'dis_cephe_kaplamasi',
};

/// DB enum -> UI etiketi
final Map<String, String> kStageEnumToLabel = {
  for (final e in kStageLabelToEnum.entries) e.value: e.key
};

/// Varsayılan kriter listesi (etiket, ağırlık)
const List<Map<String, dynamic>> kFallbackStageWeights = [
  {'stage': 'Kazı ve Zemin İşleri', 'weight': 5},
  {'stage': 'Grobeton ve Temel Hazırlık', 'weight': 5},
  {'stage': 'Temel Donatısı ve Beton', 'weight': 8},
  {'stage': 'Temel Yalıtımı (Membran)', 'weight': 2},
  {'stage': 'Bodrum Perde ve Döşemeler', 'weight': 8},
  {'stage': 'Kat Kolonları', 'weight': 10},
  {'stage': 'Kat Kirişleri', 'weight': 10},
  {'stage': 'Kat Döşemeleri', 'weight': 12},
  {'stage': 'Merdiven ve Sahanlıklar', 'weight': 5},
  {'stage': 'Duvar Örme (Tüm Katlar)', 'weight': 10},
  {'stage': 'Çatı Konstrüksiyon ve Kaplama', 'weight': 10},
  {'stage': 'Dış Cephe Kaplaması', 'weight': 15},
];

class ProjectDetailPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const ProjectDetailPage({super.key, required this.project});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;
  late final String _projectName;

  List<Map<String, dynamic>> _buildings = [];

  /// stage_weights: [{stage:<UI etiketi>, weight:<num>}]
  List<Map<String, dynamic>> _stageWeights = [];

  /// KANONİK: enum anahtarı ile tut (building_id -> { enum -> 0..100 })
  final Map<String, Map<String, double>> _buildingStagePctByEnum = {};

  /// building_id -> 0..1
  final Map<String, double> _buildingProgressRatio = {};

  /// 0..1
  double _projectProgressRatio = 0.0;

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _projectName = (widget.project['name'] ?? 'Proje').toString();
    _loadAll();
  }

  // -------------------- DATA LOAD --------------------
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      // 1) stage_weights (TEXT label)
      try {
        final sw = await supabase
            .from('stage_weights')
            .select('stage, weight')
            .eq('project_id', _projectId)
            .order('stage');

        if (sw is List && sw.isNotEmpty) {
          _stageWeights = List<Map<String, dynamic>>.from(sw);
        } else {
          _stageWeights = kFallbackStageWeights
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        _stageWeights = kFallbackStageWeights
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // 2) buildings
      final b = await supabase
          .from('project_buildings')
          .select('id, name, description, floors, floor_area_m2, created_at')
          .eq('project_id', _projectId)
          .order('created_at');
      _buildings = List<Map<String, dynamic>>.from(b as List);

      // 3) building_stages -> enums ile doldur
      try {
        final bsRows = await supabase
            .from('building_stages')
            .select('building_id, stage, completed_flt')
            .eq('project_id', _projectId);

        _buildingStagePctByEnum.clear();
        for (final r in (bsRows as List)) {
          final bId = (r['building_id'] ?? '').toString();
          final enumVal = (r['stage'] ?? '').toString(); // enum
          if (enumVal.isEmpty) continue;
          final pct =
              double.tryParse((r['completed_flt'] ?? 0).toString()) ?? 0.0;
          (_buildingStagePctByEnum[bId] ??= {})[enumVal] = pct;
        }
      } catch (_) {
        _buildingStagePctByEnum.clear();
      }

      // 4) building progress — ÖNCE TABLO, yoksa LOKAL
      _buildingProgressRatio.clear();
      try {
        final rows = await supabase
            .from('building_progress')
            .select('building_id, progress_ratio')
            .eq('project_id', _projectId);

        if (rows is List && rows.isNotEmpty) {
          for (final r in rows) {
            final bId = (r['building_id'] ?? '').toString();
            _buildingProgressRatio[bId] =
                (r['progress_ratio'] as num?)?.toDouble() ?? 0.0;
          }
        } else {
          for (final b in _buildings) {
            final bId = (b['id'] ?? '').toString();
            _buildingProgressRatio[bId] = _computeBuildingRatioLocal(bId);
          }
        }
      } catch (_) {
        for (final b in _buildings) {
          final bId = (b['id'] ?? '').toString();
          _buildingProgressRatio[bId] = _computeBuildingRatioLocal(bId);
        }
      }

      // 5) project progress — ÖNCE TABLO, yoksa LOKAL
      try {
        final row = await supabase
            .from('project_progress')
            .select('progress_ratio')
            .eq('project_id', _projectId)
            .maybeSingle();

        if (row != null) {
          _projectProgressRatio =
              (row['progress_ratio'] as num?)?.toDouble() ?? 0.0;
        } else {
          _projectProgressRatio = _computeProjectRatioLocal();
        }
      } catch (_) {
        _projectProgressRatio = _computeProjectRatioLocal();
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _err = 'Veriler alınamadı: $e';
        _loading = false;
      });
    }
  }

  // ------------ LOCAL HESAPLAR -------------
  double _computeBuildingRatioLocal(String buildingId) {
    final pctByEnum = _buildingStagePctByEnum[buildingId] ?? const {};
    if (pctByEnum.isEmpty) return 0.0;

    double sumW = 0, sumWDone = 0;
    for (final sw in _stageWeights) {
      final label = (sw['stage'] ?? '').toString();
      final enumVal = kStageLabelToEnum[label] ?? label;
      final w = (sw['weight'] is num)
          ? (sw['weight'] as num).toDouble()
          : double.tryParse('${sw['weight']}') ?? 0.0;
      final p = (pctByEnum[enumVal] ?? 0.0) / 100.0; // 0..1
      sumW += w;
      sumWDone += w * p;
    }
    if (sumW <= 0) return 0.0;
    return (sumWDone / sumW).clamp(0.0, 1.0);
  }

  double _computeProjectRatioLocal() {
    double sumWeight = 0, sumDone = 0;
    for (final b in _buildings) {
      final bId = (b['id'] ?? '').toString();
      final floors = (b['floors'] is num)
          ? (b['floors'] as num).toDouble()
          : double.tryParse('${b['floors']}') ?? 0.0;
      final area = (b['floor_area_m2'] is num)
          ? (b['floor_area_m2'] as num).toDouble()
          : double.tryParse('${b['floor_area_m2']}') ?? 0.0;
      final w = (floors <= 0 || area <= 0) ? 0.0 : (floors * area);
      final r = _buildingProgressRatio[bId] ?? _computeBuildingRatioLocal(bId);
      sumWeight += w;
      sumDone += w * r;
    }
    if (sumWeight <= 0) return 0.0;
    return (sumDone / sumWeight).clamp(0.0, 1.0);
  }

  // ----------- KAYDET -----------
  Future<void> _saveBuildingStages({
    required String buildingId,
    required Map<String, bool> stageToDoneLabel,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (final entry in stageToDoneLabel.entries) {
      final enumVal = kStageLabelToEnum[entry.key] ?? entry.key;
      if (enumVal.isEmpty) continue;
      final pct = entry.value ? 100.0 : 0.0;
      rows.add({
        'project_id': _projectId,
        'building_id': buildingId,
        'stage': enumVal,
        'completed_flt': pct,
      });
    }

    try {
      await supabase
          .from('building_stages')
          .upsert(rows, onConflict: 'project_id,building_id,stage');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('42P10') || msg.contains('no unique')) {
        await supabase
            .from('building_stages')
            .delete()
            .eq('project_id', _projectId)
            .eq('building_id', buildingId);
        if (rows.isNotEmpty) {
          await supabase.from('building_stages').insert(rows);
        }
      } else {
        rethrow;
      }
    }

    (_buildingStagePctByEnum[buildingId] ??= {}).clear();
    for (final r in rows) {
      (_buildingStagePctByEnum[buildingId] ??= {})[r['stage'] as String] =
          (r['completed_flt'] as num).toDouble();
    }

    final bRatio = _computeBuildingRatioLocal(buildingId);
    _buildingProgressRatio[buildingId] = bRatio;
    await supabase.from('building_progress').upsert({
      'project_id': _projectId,
      'building_id': buildingId,
      'progress_ratio': bRatio,
    }, onConflict: 'project_id,building_id');

    final pRatio = _computeProjectRatioLocal();
    _projectProgressRatio = pRatio;
    await supabase.from('project_progress').upsert({
      'project_id': _projectId,
      'progress_ratio': pRatio,
    }, onConflict: 'project_id');

    setState(() {});
  }

  // ---------------- BUILD ----------------
  void _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Proje ID panoya kopyalandı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final projectPct = (_projectProgressRatio * 100.0).clamp(0.0, 100.0);

    return Scaffold(
      appBar: AppBar(title: Text('Proje Detayları — $_projectName')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ✅ Proje ID + Kopyala butonu
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Proje ID'),
                subtitle: SelectableText(
                  _projectId,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: IconButton(
                  tooltip: 'Kopyala',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyToClipboard(_projectId),
                ),
              ),
            ),

            // mevcut içerik
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
                    width: 140,
                    height: 140,
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

            _buildBuildingsSection(),
            const SizedBox(height: 24),

            // Navigasyonlar
            ElevatedButton.icon(
              icon: const Icon(Icons.rule),
              label: const Text("Metraj Hesabı"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MetrajHesapPage(project: widget.project),
                ),
              ),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              icon: const Icon(Icons.warehouse),
              label: const Text("Stok Takip"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => StokTakipPage(project: project)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text("Fotoğraf / Video Arşivi"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MediaArsivPage(project: project)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("Şantiye Raporları"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => RaporlarPage(project: project)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.group),
              label: const Text("Personel ve Ücret Takibi"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PersonelTakipPage(project: project)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingsSection() {
    if (_buildings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Yapılar / Bloklar', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._buildings.map((b) {
          final buildingId = (b['id'] ?? '').toString();
          final name = (b['name'] ?? 'Yapı').toString();
          final desc = (b['description'] ?? '').toString();
          final floors = (b['floors'] ?? 0).toString();
          final ratio =
          (_buildingProgressRatio[buildingId] ?? 0.0).clamp(0.0, 1.0);
          final pct = (ratio * 100.0).toStringAsFixed(0);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('İlerleme Ekle/Düzenle'),
                      onPressed: () =>
                          _openStageEditorForBuilding(buildingId, name),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------- İLERLEME DİYALOĞU ----------
  void _openStageEditorForBuilding(String buildingId, String buildingName) {
    final Map<String, bool> currentDone = {};
    final pctByEnum = _buildingStagePctByEnum[buildingId] ?? {};
    final source =
    _stageWeights.isNotEmpty ? _stageWeights : kFallbackStageWeights;

    for (final sw in source) {
      final label = (sw['stage'] ?? '').toString();
      final enumVal = kStageLabelToEnum[label] ?? label;
      currentDone[label] = (pctByEnum[enumVal] ?? 0.0) >= 100.0;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('İlerleme — $buildingName',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.55,
                    child: ListView.separated(
                      itemCount: source.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (_, i) {
                        final label = (source[i]['stage'] ?? '').toString();
                        final weight =
                        (source[i]['weight'] ?? '').toString();
                        final checked = currentDone[label] ?? false;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: checked,
                          onChanged: (v) {
                            setModal(() {
                              currentDone[label] = v ?? false;
                            });
                          },
                          title: Text(label),
                          secondary: Text('Ağırlık: $weight',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700)),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('İptal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text('Kaydet'),
                          onPressed: () async {
                            try {
                              await _saveBuildingStages(
                                buildingId: buildingId,
                                stageToDoneLabel: currentDone,
                              );
                              if (mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('İlerleme kaydedildi.')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Kayıt hatası: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
