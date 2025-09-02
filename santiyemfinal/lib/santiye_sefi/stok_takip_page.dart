import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';

class StokTakipPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const StokTakipPage({super.key, required this.project});

  @override
  State<StokTakipPage> createState() => _StokTakipPageState();
}

class _StokTakipPageState extends State<StokTakipPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;

  // Katalog
  List<Map<String, dynamic>> _materials = [];

  // Giriş/Çıkış toplamları
  final Map<String, double> _sumIn = {};
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
      // 1) Katalog
      final mats = await supabase
          .from('material_catalog')
          .select('id, name, default_unit')
          .order('name');
      _materials = List<Map<String, dynamic>>.from(mats as List);

      // 2) Giriş/Çıkış agregasyonları (quantity!)
      _sumIn.clear();
      _sumOut.clear();

      final ins = await supabase
          .from('material_transactions')
          .select('material_id, quantity')
          .eq('project_id', _projectId)
          .eq('direction', 'in');
      for (final r in (ins as List)) {
        final mid = (r['material_id'] ?? '').toString();
        final q = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        _sumIn[mid] = (_sumIn[mid] ?? 0) + q;
      }

      final outs = await supabase
          .from('material_transactions')
          .select('material_id, quantity')
          .eq('project_id', _projectId)
          .eq('direction', 'out');
      for (final r in (outs as List)) {
        final mid = (r['material_id'] ?? '').toString();
        final q = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        _sumOut[mid] = (_sumOut[mid] ?? 0) + q;
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() { _err = 'Veri yüklenemedi: $e'; _loading = false; });
    }
  }

  double _totalIn(String materialId) => (_sumIn[materialId] ?? 0.0);
  double _used(String materialId) => (_sumOut[materialId] ?? 0.0);
  double _remaining(String materialId) =>
      (_totalIn(materialId) - _used(materialId)).clamp(0.0, double.infinity);
  double _remainingPercent(String materialId) {
    final tot = _totalIn(materialId);
    if (tot <= 0) return 0.0;
    return (_remaining(materialId) / tot).clamp(0.0, 1.0);
  }

  // Stok EKLE (giriş)
  Future<void> _addDialog({
    required String materialId,
    required String matName,
    required String unit,
  }) async {
    final tcQty = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stok Ekle — $matName'),
        content: TextField(
          controller: tcQty,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Miktar ($unit)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;

    final qty = double.tryParse(tcQty.text.replaceAll(',', '.')) ?? 0.0;
    if (qty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Miktar > 0 olmalı.')),
        );
      }
      return;
    }

    try {
      await supabase.from('material_transactions').insert({
        'project_id': _projectId,
        'material_id': materialId,
        'quantity': qty,        // <-- quantity
        'direction': 'in',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stok ekleme hatası: $e')),
        );
      }
    }

    await _loadAll();
  }

  // Kullanım ekle (çıkış)
  Future<void> _useDialog({
    required String materialId,
    required String matName,
    required String unit,
  }) async {
    final tcQty = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kullan — $matName'),
        content: TextField(
          controller: tcQty,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Miktar ($unit)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;

    final qty = double.tryParse(tcQty.text.replaceAll(',', '.')) ?? 0.0;
    if (qty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Miktar > 0 olmalı.')),
        );
      }
      return;
    }

    final remain = _remaining(materialId);
    if (qty > remain + 1e-9) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kalan stoğu aşamazsın. Kalan: ${remain.toStringAsFixed(2)} $unit')),
        );
      }
      return;
    }

    try {
      await supabase.from('material_transactions').insert({
        'project_id': _projectId,
        'material_id': materialId,
        'quantity': qty,        // <-- quantity
        'direction': 'out',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kullanım kaydı hatası: $e')),
        );
      }
    }

    await _loadAll();
  }

  Widget _chip(String text) => Chip(
    label: Text(text),
    backgroundColor: Colors.grey.shade100,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _ring(double pct) {
    return SizedBox(
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
  }

  Widget _buildRow(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final name = (m['name'] ?? '').toString();
    final unit = (m['default_unit'] ?? '').toString();

    final total = _totalIn(id);
    final used = _used(id);
    final remain = _remaining(id);
    final remainPct = _remainingPercent(id);

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
                  _ring(remainPct),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Stok Ekle'),
                    onPressed: () => _addDialog(
                      materialId: id,
                      matName: name,
                      unit: unit,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.remove_shopping_cart),
                    label: const Text('Kullan'),
                    onPressed: () => _useDialog(
                      materialId: id,
                      matName: name,
                      unit: unit,
                    ),
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
      appBar: AppBar(title: const Text('Stok Takip')),
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
