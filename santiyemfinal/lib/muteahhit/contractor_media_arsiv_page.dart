import 'package:flutter/material.dart';
import 'package:santiyemfinal/supabase_client.dart';
import 'package:video_player/video_player.dart';

class ContractorMediaArsivPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const ContractorMediaArsivPage({super.key, required this.project});

  @override
  State<ContractorMediaArsivPage> createState() => _ContractorMediaArsivPageState();
}

class _ContractorMediaArsivPageState extends State<ContractorMediaArsivPage> {
  bool _loading = true;
  String? _err;

  late final String _projectId;

  final List<_MediaItem> _items = [];
  String _query = '';
  _MediaKind _filter = _MediaKind.all;

  @override
  void initState() {
    super.initState();
    _projectId = (widget.project['id'] ?? '').toString();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _err = null; });

    try {
      final rows = await supabase
          .from('project_media')
          .select('id,name,kind,url,thumbnail_url,created_at')
          .eq('project_id', _projectId)
          .order('created_at', ascending: false);

      _items
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(rows).map((r) {
          final k = ((r['kind'] ?? 'photo') as String) == 'video'
              ? _MediaKind.video
              : _MediaKind.photo;
          return _MediaItem(
            id: (r['id'] ?? '').toString(),
            name: (r['name'] ?? '').toString(),
            url: (r['url'] ?? '').toString(),
            thumbnailUrl: (r['thumbnail_url'] as String?),
            kind: k,
            createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now(),
          );
        }));

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = 'Medya yüklenemedi: $e'; _loading = false; });
    }
  }

  List<_MediaItem> get _visibleItems {
    final q = _query.trim().toLowerCase();
    return _items.where((m) {
      final typeOk = _filter == _MediaKind.all ||
          (_filter == _MediaKind.photo && m.kind == _MediaKind.photo) ||
          (_filter == _MediaKind.video && m.kind == _MediaKind.video);
      final searchOk = q.isEmpty || m.name.toLowerCase().contains(q);
      return typeOk && searchOk;
    }).toList();
  }

  void _openItem(_MediaItem item) {
    if (item.kind == _MediaKind.photo) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _PhotoViewer(item: item)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _VideoPlayerPage(url: item.url, title: item.name),
        ),
      );
    }
  }

  // ---------- UI ----------
  Widget _buildTile(_MediaItem m) {
    final thumb = m.thumbnailUrl ?? (m.kind == _MediaKind.photo ? m.url : null);

    return GestureDetector(
      onTap: () => _openItem(m),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 1.5,
        child: Stack(
          children: [
            Positioned.fill(
              child: thumb != null
                  ? Image.network(
                thumb,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbPlaceholder(m.kind),
                loadingBuilder: (c, w, prog) =>
                prog == null ? w : const Center(child: CircularProgressIndicator()),
              )
                  : _thumbPlaceholder(m.kind),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      m.kind == _MediaKind.photo ? Icons.photo : Icons.play_arrow,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      m.kind == _MediaKind.photo ? 'Foto' : 'Video',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (m.kind == _MediaKind.video)
              const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 56),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(m.createdAt),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(_MediaKind kind) {
    return Container(
      color: Colors.grey.shade300,
      child: Icon(
        kind == _MediaKind.photo ? Icons.broken_image : Icons.movie,
        color: Colors.grey.shade600,
        size: 40,
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Tümü', _MediaKind.all),
              const SizedBox(width: 8),
              _filterChip('Fotoğraflar', _MediaKind.photo),
              const SizedBox(width: 8),
              _filterChip('Videolar', _MediaKind.video),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Ara (isim)...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _MediaKind k) {
    final selected = _filter == k;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = k),
      selectedColor: Colors.teal.shade100,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Colors.teal : Colors.grey.shade300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Fotoğraf / Video Arşivi')),
      // 👇 MÜTEAHHİTTE YÜKLEME YOK → FAB YOK
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!))
          : RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Henüz medya yok.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                // 🔧 BURASI: 'child' değil 'sliver'
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildTile(items[index]),
                    childCount: items.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}

enum _MediaKind { all, photo, video }

class _MediaItem {
  final String id;
  final String name;
  final String url;
  final String? thumbnailUrl;
  final _MediaKind kind;
  final DateTime createdAt;

  _MediaItem({
    required this.id,
    required this.name,
    required this.url,
    this.thumbnailUrl,
    required this.kind,
    required this.createdAt,
  });
}

class _PhotoViewer extends StatelessWidget {
  final _MediaItem item;
  const _PhotoViewer({required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.network(
            item.url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
          ),
        ),
      ),
    );
  }
}

/// Basit uygulama içi video oynatıcı
class _VideoPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  const _VideoPlayerPage({super.key, required this.url, required this.title});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((e) {
        if (!mounted) return;
        setState(() => _err = 'Video açılamadı: $e');
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _err != null
          ? Center(child: Text(_err!))
          : !_ready
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
        onTap: () {
          if (_controller.value.isPlaying) {
            _controller.pause();
          } else {
            _controller.play();
          }
          setState(() {});
        },
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller.value.aspectRatio == 0
                ? 16 / 9
                : _controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller),
                if (!_controller.value.isPlaying)
                  const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _ready
          ? FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
      )
          : null,
    );
  }
}
