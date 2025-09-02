import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart'; // Supabase bağlantısı

class PersonelTakipPage extends StatefulWidget {
  final Map<String, dynamic> project;

  const PersonelTakipPage({super.key, required this.project});

  @override
  State<PersonelTakipPage> createState() => _PersonelTakipPageState();
}

class _PersonelTakipPageState extends State<PersonelTakipPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController roleController = TextEditingController();
  final TextEditingController daysController = TextEditingController();
  final TextEditingController dailyWageController = TextEditingController();

  /// {id, name, role, daysMonthly, dailyWage, totalMonthly}
  final List<Map<String, dynamic>> personnel = [];

  double get totalMonthlyPayroll {
    return personnel.fold<double>(
      0.0,
          (sum, p) => sum + ((p['totalMonthly'] as num?)?.toDouble() ?? 0.0),
    );
  }

  @override
  void initState() {
    super.initState();
    loadPersonnel(); // Sayfa açılınca mevcut kayıtları çek
  }

  Future<void> loadPersonnel() async {
    try {
      final data = await supabase
          .from('personnel_records')
          .select()
          .eq('project_id', widget.project['id'])
          .order('created_at');

      setState(() {
        personnel
          ..clear()
          ..addAll(data.map<Map<String, dynamic>>((p) {
            final days = (p['days'] as num).toDouble();
            final wage = (p['daily_wage'] as num).toDouble();
            return {
              'id': p['id'],
              'name': p['name'],
              'role': p['role'],
              'daysMonthly': days.toInt(),
              'dailyWage': wage,
              'totalMonthly': days * wage,
            };
          }));
      });
    } catch (e) {
      debugPrint("❌ Personel yükleme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Personel listesi alınamadı: $e")),
        );
      }
    }
  }

  Future<void> addPersonnel() async {
    final name = nameController.text.trim();
    final role = roleController.text.trim();
    final daysMonthly = int.tryParse(daysController.text.trim()) ?? 0;
    final dailyWage =
        double.tryParse(dailyWageController.text.trim().replaceAll(',', '.')) ??
            0;

    if (name.isEmpty || role.isEmpty || daysMonthly <= 0 || dailyWage <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen tüm alanları doğru doldurun.")),
      );
      return;
    }

    try {
      final insertRes = await supabase.from('personnel_records').insert({
        'project_id': widget.project['id'],
        'name': name,
        'role': role,
        'days': daysMonthly,
        'daily_wage': dailyWage,
      }).select();

      if (insertRes.isNotEmpty) {
        final newRow = insertRes.first;
        setState(() {
          personnel.insert(0, {
            'id': newRow['id'],
            'name': name,
            'role': role,
            'daysMonthly': daysMonthly,
            'dailyWage': dailyWage,
            'totalMonthly': daysMonthly * dailyWage,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Personel başarıyla eklendi.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Kayıt hatası: $e")),
      );
    }

    nameController.clear();
    roleController.clear();
    daysController.clear();
    dailyWageController.clear();
  }

  Future<void> _showEditDialog(Map<String, dynamic> p, int index) async {
    final editName = TextEditingController(text: p['name']?.toString() ?? '');
    final editRole = TextEditingController(text: p['role']?.toString() ?? '');
    final editDays =
    TextEditingController(text: p['daysMonthly']?.toString() ?? '');
    final editWage =
    TextEditingController(text: p['dailyWage']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Personel Düzenle"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: editName,
                  decoration: const InputDecoration(
                      labelText: "Ad Soyad", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: editRole,
                  decoration: const InputDecoration(
                      labelText: "Görev", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: editDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: "Aylık Gün", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: editWage,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: "Günlük Ücret (₺)",
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Vazgeç"),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text("Kaydet"),
              onPressed: () async {
                final newName = editName.text.trim();
                final newRole = editRole.text.trim();
                final newDays = int.tryParse(editDays.text.trim()) ?? 0;
                final newWage = double.tryParse(
                    editWage.text.trim().replaceAll(',', '.')) ??
                    0;

                if (newName.isEmpty ||
                    newRole.isEmpty ||
                    newDays <= 0 ||
                    newWage <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Lütfen tüm alanları doğru doldurun.")),
                  );
                  return;
                }

                try {
                  final updated = await supabase
                      .from('personnel_records')
                      .update({
                    'name': newName,
                    'role': newRole,
                    'days': newDays,
                    'daily_wage': newWage,
                  })
                      .eq('id', p['id'])
                      .select();

                  if (updated.isNotEmpty) {
                    setState(() {
                      personnel[index] = {
                        'id': p['id'],
                        'name': newName,
                        'role': newRole,
                        'daysMonthly': newDays,
                        'dailyWage': newWage,
                        'totalMonthly': newDays * newWage,
                      };
                    });
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Kayıt güncellendi.")),
                      );
                    }
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Güncelleme hatası: $e")),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePersonnel(Map<String, dynamic> p, int index) async {
    final agree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Silinsin mi?"),
        content: Text("${p['name']} (${p['role']}) kaydı silinecek."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Vazgeç")),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text("Sil"),
          ),
        ],
      ),
    );

    if (agree != true) return;

    try {
      await supabase.from('personnel_records').delete().eq('id', p['id']);
      setState(() => personnel.removeAt(index));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Kayıt silindi.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Silme hatası: $e")),
        );
      }
    }
  }

  String _money(num v) => "₺${v.toStringAsFixed(2)}";

  @override
  Widget build(BuildContext context) {
    final projectName = widget.project['name'] ?? 'Proje';
    final projectId = widget.project['id'] ?? 'id-yok';

    return Scaffold(
      appBar: AppBar(
        title: Text("Personel Takibi - $projectName"),
        actions: [
          IconButton(
            tooltip: "Yenile",
            onPressed: loadPersonnel,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Proje ID: $projectId",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),

              const Text("Yeni Personel Ekle",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: "Ad Soyad", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: roleController,
                decoration: const InputDecoration(
                    labelText: "Görevi", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: daysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Aylık Çalıştığı Gün Sayısı",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dailyWageController,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Günlük Ücret (₺)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: addPersonnel,
                icon: const Icon(Icons.person_add),
                label: const Text("Ekle"),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Personel Listesi",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: personnel.length,
                itemBuilder: (context, index) {
                  final p = personnel[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.person),
                      title: Text("${p['name']} • ${p['role']}"),
                      subtitle: Text(
                        "Gün: ${p['daysMonthly']}  |  Günlük: ${_money(p['dailyWage'])}\n"
                            "Aylık Toplam: ${_money(p['totalMonthly'])}",
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'edit') _showEditDialog(p, index);
                          if (val == 'delete') _deletePersonnel(p, index);
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
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
              ),

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
                    const Text("Toplam Aylık Personel Maliyeti",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      _money(totalMonthlyPayroll),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
