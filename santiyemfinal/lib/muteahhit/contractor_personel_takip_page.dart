import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';

class ContractorPersonelTakipPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const ContractorPersonelTakipPage({super.key, required this.project});

  @override
  State<ContractorPersonelTakipPage> createState() => _ContractorPersonelTakipPageState();
}

class _ContractorPersonelTakipPageState extends State<ContractorPersonelTakipPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;
  late final String _projectName;

  /// {id, name, role, daysMonthly, dailyWage, totalMonthly}
  final List<Map<String, dynamic>> _personnel = [];

  double get _totalMonthlyPayroll =>
      _personnel.fold<double>(0.0, (sum, p) => sum + ((p['totalMonthly'] as num?)?.toDouble() ?? 0.0));

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _projectName = (widget.project['name'] ?? 'Proje').toString();
    _loadPersonnel();
  }

  Future<void> _loadPersonnel() async {
    setState(() { _loading = true; _err = null; });
    try {
      final data = await supabase
          .from('personnel_records')
          .select('id,name,role,days,daily_wage,created_at')
          .eq('project_id', _projectId)
          .order('created_at');

      _personnel
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(data).map((p) {
          final days = (p['days'] as num?)?.toDouble() ?? 0.0;
          final wage = (p['daily_wage'] as num?)?.toDouble() ?? 0.0;
          return {
            'id': p['id'],
            'name': (p['name'] ?? '').toString(),
            'role': (p['role'] ?? '').toString(),
            'daysMonthly': days.toInt(),
            'dailyWage': wage,
            'totalMonthly': days * wage,
          };
        }));

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = 'Personel listesi alınamadı: $e'; _loading = false; });
    }
  }

  String _money(num v) => '₺${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Personel Takibi — $_projectName'),
        actions: [
          IconButton(onPressed: _loadPersonnel, icon: const Icon(Icons.refresh), tooltip: 'Yenile'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!))
          : _personnel.isEmpty
          ? const Center(child: Text('Henüz personel kaydı yok.'))
          : RefreshIndicator(
        onRefresh: _loadPersonnel,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ..._personnel.map((p) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text('${p['name']} • ${p['role']}'),
                subtitle: Text(
                  'Gün: ${p['daysMonthly']}  |  Günlük: ${_money(p['dailyWage'])}\n'
                      'Aylık Toplam: ${_money(p['totalMonthly'])}',
                ),
                isThreeLine: true,
              ),
            )),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Toplam Aylık Personel Maliyeti',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_money(_totalMonthlyPayroll),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
