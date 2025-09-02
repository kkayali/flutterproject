import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';

class ContractorStokTakipPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const ContractorStokTakipPage({super.key, required this.project});

  @override
  State<ContractorStokTakipPage> createState() => _ContractorStokTakipPageState();
}

class _ContractorStokTakipPageState extends State<ContractorStokTakipPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;

  // Katalog
  List<Map<String, dynamic>> _materials = [];

  // Giriş/Çıkış toplamları (quantity kolonu)
  final Map<String, double> _sumIn  = {};
  final Map<String, double> _sumOut = {};

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _err = null; });

    try {
      // 1) KATALOG
      debugPrint('🧭 [CTR-STOCK] material_catalog okunuyor…');
      final mats = await supabase
          .from('material_catalog')
          .select('id, name, default_unit')
          .order('name');
      _materials = List<Map<String, dynamic>>.from(mats as List);

      // 2) AGREGASYONLAR (sadece OKUMA)
      _sumIn.clear();
      _sumOut.clear();

      debugPrint('🧭 [CTR-STOCK] material_transactions (in)…');
      final ins = await supabase
          .from('material_transactions')
          .select('material_id, quantity')
          .eq('project_id', _projectId)
          .eq('direction', 'in');

      for (final r in (ins as List)) {
        final mid = (r['material_id'] ?? '').toString();
        final q   = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        _sumIn[mid] = (_sumIn[mid] ?? 0) + q;
      }

      debugPrint('🧭 [CTR-STOCK] material_transactions (out)…');
      final outs = await supabase
          .from('material_transactions')
          .select('material_id, quantity')
          .eq('project_id', _projectId)
          .eq('direction', 'out');

      for (final r in (outs as List)) {
        final mid = (r['material_id'] ?? '').toString();
        final q   = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        _sumOut[mid] = (_sumOut[mid] ?? 0) + q;
      }

      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('✅ [CTR-STOCK] Yükleme tamam. Katalog=${_materials.length}');
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = 'Veri yüklenemedi: $e'; _loading = false; });
      debugPrint('❌ [CTR-STOCK] Hata: $e');
    }
  }

  double _totalIn(String materialId) => (_sumIn[materialId] ?? 0.0);
  double _used(String materialId)     => (_sumOut[materialId] ?? 0.0);
  double _remaining(String materialId) =>
      (_totalIn(materialId) - _used(materialId)).clamp(0.0, double.infinity);
  double _remainingPercent(String materialId) {
    final tot = _totalIn(materialId);
    if (tot <= 0) return 0.0;
    return (_remaining(materialId) / tot).clamp(0.0, 1.0);
  }

  Widget _chip(String text) => Chip(
    label: Text(text),
    backgroundColor: Colors.grey.shade100,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _ring(double pct) => SizedBox(
    width: 42,
    height: 42,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          strokeWidth: 6,
          value: pct,
          backgroundColor: Colors.grey.shade300,
        ),
        Text('${(pct * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  Widget _buildRow(Map<String, dynamic> m) {
    final id   = (m['id'] ?? '').toString();
    final name = (m['name'] ?? '').toString();
    final unit = (m['default_unit'] ?? '').toString();

    final total    = _totalIn(id);
    final used     = _used(id);
    final remain   = _remaining(id);
    final remainPc = _remainingPercent(id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2),
              title: Row(
                children: [
                  Expanded(child: Text(name)),
                  const SizedBox(width: 8),
                  _ring(remainPc),
                ],
              ),
              subtitle: Text('Birim: $unit'),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _chip('Toplam: ${total.toStringAsFixed(2)} $unit'),
                _chip('Kullanım: ${used.toStringAsFixed(2)} $unit'),
                _chip('Kalan: ${remain.toStringAsFixed(2)} $unit'),
              ],
            ),
            const SizedBox(height: 8),
            // 🔒 Müteahhit salt-okuma: buton yok
            const Text('Şantiye şefi günceller, siz burada takip edersiniz.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stok Takip (Müteahhit – Salt Okuma)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!))
          : _materials.isEmpty
          ? const Center(child: Text('Katalog boş.'))
          : RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _materials.length,
          itemBuilder: (_, i) => _buildRow(_materials[i]),
        ),
      ),
    );
  }
}
