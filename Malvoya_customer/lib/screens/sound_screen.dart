import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../widgets/drop_grid.dart';
import 'drops_feed.dart';

/// A sound from Malvoya's music library: its title and artist, how many drops use it, a preview of the
/// track and those drops as a grid. Tapping a drop opens the reel at that drop over the same list.
class SoundScreen extends StatefulWidget {
  final int soundId;

  /// Shown until the sound has loaded (taken from the drop that was tapped).
  final String? title;
  final String? artist;

  const SoundScreen({super.key, required this.soundId, this.title, this.artist});

  @override
  State<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends State<SoundScreen> {
  Map<String, dynamic>? _sound;
  String? _error;
  VideoPlayerController? _preview;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/sounds/${widget.soundId}');
    if (!mounted) return;
    setState(() {
      if (res.ok && res.data['sound'] is Map) {
        _sound = Map<String, dynamic>.from(res.data['sound']);
        _error = null;
      } else {
        _error = res.errorText(context) ?? tr(context, 'Could not load the sound.', 'Äänen lataaminen ei onnistunut.');
      }
    });
  }

  String get _title => (_sound?['title'] ?? widget.title ?? '').toString();
  String get _artist => (_sound?['artist'] ?? widget.artist ?? '').toString();

  Future<void> _togglePreview() async {
    final playing = _preview?.value.isPlaying ?? false;
    if (playing) {
      await _preview!.pause();
      if (mounted) setState(() {});
      return;
    }
    if (_preview != null) {
      await _preview!.play();
      if (mounted) setState(() {});
      return;
    }
    final url = _sound?['url'];
    if (url is! String || _previewLoading) return;
    setState(() => _previewLoading = true);
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (!mounted) return;
      setState(() => _previewLoading = false);
      MSnack.error(context, tr(context, 'The sound could not be played.', 'Ääntä ei voitu toistaa.'));
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(() {
      if (!mounted) return;
      final v = c.value;
      // Back to the start when the preview ends, ready to play again
      if (v.isInitialized && !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration) {
        c.seekTo(Duration.zero);
      }
      setState(() {});
    });
    // Playing a preview is the listener's own choice, so it plays even when videos are muted
    await c.setVolume(1);
    setState(() {
      _preview = c;
      _previewLoading = false;
    });
    await c.play();
  }

  Future<void> _openReel(List<Map<String, dynamic>> drops, String? cursor, int dropId) async {
    if (_preview?.value.isPlaying ?? false) {
      await _preview!.pause();
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DropsFeedScreen(
          soundId: widget.soundId,
          title: _title,
          startDropId: dropId,
          initialDrops: drops,
          initialCursor: cursor,
        ),
      ),
    );
  }

  String _duration(dynamic sec) {
    final s = (sec is num ? sec : num.tryParse('${sec ?? ''}') ?? 0).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _header(BuildContext context) {
    final uses = asInt(_sound?['useCount']);
    final playing = _preview?.value.isPlaying ?? false;
    final canPlay = _sound?['url'] is String;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.lg),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(MRadius.sm)),
            child: const Icon(Icons.music_note_rounded, size: 36, color: AppTheme.primary),
          ),
          const SizedBox(width: MSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: AppTheme.primaryText(context))),
                if (_artist.isNotEmpty)
                  Text(_artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.secondaryText(context), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (uses != null) uses == 1 ? tr(context, '1 drop', '1 droppi') : tr(context, '$uses drops', '$uses droppia'),
                    if (_sound?['durationSec'] != null) _duration(_sound!['durationSec']),
                  ].join(' · '),
                  style: TextStyle(color: AppTheme.secondaryText(context), fontSize: MTextSize.caption),
                ),
              ],
            ),
          ),
          const SizedBox(width: MSpace.sm),
          _previewLoading
              ? const SizedBox(width: 48, height: 48, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.5)))
              : IconButton.filled(
                  tooltip: playing ? tr(context, 'Pause preview', 'Keskeytä esikuuntelu') : tr(context, 'Play preview', 'Kuuntele'),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: canPlay ? _togglePreview : null,
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Sound', 'Ääni'))),
      body: PagedDropGrid(
        path: '/sounds/${widget.soundId}/drops',
        onOpen: _openReel,
        onRefresh: _load,
        header: [
          SliverToBoxAdapter(
            child: _error != null && _sound == null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 0),
                    child: Text(_error!, style: TextStyle(color: AppTheme.secondaryText(context))),
                  )
                : _header(context),
          ),
        ],
        empty: MStateMessage(
          icon: Icons.music_note_rounded,
          scrollable: false,
          top: MSpace.xl,
          message: tr(context, 'No drops use this sound right now.', 'Tätä ääntä ei käytetä nyt yhdessäkään dropissa.'),
        ),
      ),
    );
  }
}
