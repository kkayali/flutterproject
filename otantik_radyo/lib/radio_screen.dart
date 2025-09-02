import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:intl/intl.dart';
import 'supabase.dart';
import 'admin_login_screen.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final player = AudioPlayer();
  final List<String> channels = ['pop', 'slow', 'arabesk', 'turku'];
  int currentChannelIndex = 0;
  List<Map<String, dynamic>> currentSongs = [];
  int currentSongIndex = 0;
  bool isPlaying = false;
  double _scale = 1.0;
  bool showDecor = true;

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> loadSongsForChannel() async {
    final channel = channels[currentChannelIndex];
    final streamResponse = await supabase
        .from('channel_settings')
        .select('start_time')
        .eq('channel', channel)
        .maybeSingle();

    final startTimeString = streamResponse?['start_time'];
    if (startTimeString == null) return;

    final startTime = DateTime.parse(startTimeString);
    final now = DateTime.now();
    final elapsed = now.difference(startTime).inSeconds;

    final response = await supabase
        .from('songs')
        .select()
        .eq('channel', channel)
        .eq('is_active', true)
        .order('order', ascending: true);

    final songList = List<Map<String, dynamic>>.from(response);
    if (songList.isEmpty) return;

    List<int> durations = songList.map<int>((s) {
      final dur = s['duration'];
      if (dur is int) return dur;
      if (dur is double) return dur.toInt();
      if (dur is String) return int.tryParse(dur) ?? 0;
      return 0;
    }).toList();

    int totalDuration = durations.fold(0, (a, b) => a + b);
    if (totalDuration == 0) return;

    int elapsedMod = elapsed % totalDuration;
    int index = 0, position = 0;

    for (int i = 0; i < durations.length; i++) {
      if (elapsedMod < durations[i]) {
        index = i;
        position = elapsedMod;
        break;
      } else {
        elapsedMod -= durations[i];
      }
    }

    await player.setUrl(songList[index]['url']);
    await player.seek(Duration(seconds: position));
    await player.play();

    setState(() {
      currentSongs = songList;
      currentSongIndex = index;
      isPlaying = true;
    });
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await player.stop();
      setState(() => isPlaying = false);
    } else {
      await loadSongsForChannel();
    }
  }

  Future<void> changeChannel(bool next) async {
    if (isPlaying) return; // Yayın açıkken kanal değiştirilemez
    setState(() {
      currentChannelIndex = (currentChannelIndex + (next ? 1 : -1) + channels.length) % channels.length;
      currentSongs = [];
      currentSongIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = currentSongs.isNotEmpty ? currentSongs[currentSongIndex] : null;
    final timeNow = DateFormat('HH:mm').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFF3E2723),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4E342E), Color(0xFF3E2723)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: Image.asset(
                  'assets/radio.png',
                  height: MediaQuery.of(context).size.height * 0.5,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: showDecor ? 1.0 : 0.0,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amberAccent, width: 1.3),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.music_note, color: Colors.amberAccent),
                          const SizedBox(width: 8),
                          Text(
                            channels[currentChannelIndex].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Raleway',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentSong?['title'] ?? 'Yayında şarkı yok',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Raleway',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (currentSong != null)
                Container(
                  height: 35,
                  width: double.infinity,
                  color: Colors.black87,
                  child: Marquee(
                    text: '${currentSong['title']} - ${currentSong['artist'] ?? ''}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Raleway',
                    ),
                    scrollAxis: Axis.horizontal,
                    blankSpace: 50.0,
                    velocity: 35.0,
                    startPadding: 20.0,
                  ),
                ),
              const SizedBox(height: 10),
              Divider(color: Colors.white.withOpacity(0.3), thickness: 0.8),
              const Spacer(),
              Text(
                'Saat: $timeNow',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontFamily: 'Raleway',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      onTap: () => changeChannel(false),
                      enabled: !isPlaying,
                      child: CustomPaint(
                        size: const Size(60, 60),
                        painter: TriangleButtonPainter(direction: TriangleDirection.left),
                      ),
                    ),
                    _buildControlButton(
                      onTap: togglePlayPause,
                      enabled: true,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 40,
                          color: Colors.brown.shade800,
                        ),
                      ),
                    ),
                    _buildControlButton(
                      onTap: () => changeChannel(true),
                      enabled: !isPlaying,
                      child: CustomPaint(
                        size: const Size(60, 60),
                        painter: TriangleButtonPainter(direction: TriangleDirection.right),
                      ),
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

  Widget _buildControlButton({required Widget child, required VoidCallback onTap, required bool enabled}) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: enabled ? onTap : null,
      child: Transform.scale(
        scale: _scale,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54, width: 1.2),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

enum TriangleDirection { left, right }

class TriangleButtonPainter extends CustomPainter {
  final TriangleDirection direction;
  TriangleButtonPainter({required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    if (direction == TriangleDirection.left) {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    }
    path.close();

    canvas.drawShadow(path, Colors.brown.shade900, 6, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
