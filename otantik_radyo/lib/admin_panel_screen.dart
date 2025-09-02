import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'supabase.dart';
import 'package:file_selector/file_selector.dart';
import 'package:just_audio/just_audio.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  String selectedChannel = 'pop';
  List<Map<String, dynamic>> songs = [];

  @override
  void initState() {
    super.initState();
    fetchSongs();
  }

  Future<void> fetchSongs() async {
    final response = await supabase
        .from('songs')
        .select()
        .eq('channel', selectedChannel)
        .order('order', ascending: true);
    setState(() {
      songs = List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> uploadMp3() async {
    final typeGroup = XTypeGroup(label: 'mp3', extensions: ['mp3']);
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

    if (file != null) {
      final rawName = file.name;
      final fileName = sanitizeFileName(rawName);
      final Uint8List fileBytes = await file.readAsBytes();
      final storagePath = 'channels/$selectedChannel/$fileName';

      await supabase.storage.from('music').uploadBinary(storagePath, fileBytes);
      final publicUrl = supabase.storage.from('music').getPublicUrl(storagePath);

      final tempPlayer = AudioPlayer();
      await tempPlayer.setUrl(publicUrl);
      await tempPlayer.load(); // bekleyerek süreyi garantiye al
      final duration = tempPlayer.duration ?? Duration.zero;
      await tempPlayer.dispose();

      await supabase.from('songs').insert({
        'channel': selectedChannel,
        'title': rawName, // orijinal başlığı koru
        'url': publicUrl,
        'is_active': false,
        'duration': duration.inSeconds,
      });

      fetchSongs();
    }
  }

  String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[^\w\s.-]'), '')
        .replaceAll(' ', '_');
  }



  Future<void> toggleActive(String id, bool isActive) async {
    await supabase.from('songs').update({
      'is_active': !isActive,
      'order': null,
    }).eq('id', id);

    fetchSongs();
  }

  Future<void> refreshOrder() async {
    final activeSongs = songs.where((s) => s['is_active'] == true).toList();

    for (int i = 0; i < activeSongs.length; i++) {
      final songId = activeSongs[i]['id'];
      await supabase.from('songs').update({'order': i}).eq('id', songId);
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Yayın sırası güncellendi.'),
    ));

    fetchSongs();
  }

  Future<void> startBroadcast() async {
    final now = DateTime.now().toIso8601String();
    final response = await supabase
        .from('channel_settings')
        .select()
        .eq('channel', selectedChannel)
        .maybeSingle();

    if (response == null) {
      await supabase.from('channel_settings').insert({
        'channel': selectedChannel,
        'start_time': now,
      });
    } else {
      await supabase
          .from('channel_settings')
          .update({'start_time': now})
          .eq('channel', selectedChannel);
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Yayın başlatıldı.'),
    ));
  }

  Future<void> deleteSong(String id) async {
    final response = await supabase.from('songs').select().eq('id', id).maybeSingle();
    if (response != null) {
      final url = response['url'];
      final bucketPath = _extractPathFromUrl(url);
      await supabase.storage.from('music').remove([bucketPath]);
    }
    await supabase.from('songs').delete().eq('id', id);
    fetchSongs();
  }

  String _extractPathFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    final musicIndex = segments.indexOf('music');
    return segments.sublist(musicIndex + 1).join('/');
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = songs.where((s) => s['is_active'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          DropdownButton<String>(
            value: selectedChannel,
            underline: Container(),
            dropdownColor: Colors.brown[800],
            style: const TextStyle(color: Colors.white),
            items: ['pop', 'slow', 'arabesk', 'turku']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedChannel = value;
                });
                fetchSongs();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: uploadMp3,
          ),
        ],
      ),
      body: Column(
        children: [
          if (activeCount > 0)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '$activeCount aktif şarkı seçildi.',
                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: activeCount > 0 ? refreshOrder : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Yenile (Sırala)"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: activeCount > 0 ? startBroadcast : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Yayını Başlat"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return ListTile(
                  title: Text(song['title'] ?? 'Unknown'),
                  leading: Checkbox(
                    value: song['is_active'] ?? false,
                    onChanged: (_) => toggleActive(song['id'], song['is_active']),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteSong(song['id']),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
