import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core/media_sound.dart';
import '../core/strings.dart';

/// A product video with sound: shows the poster at once, streams (HLS, with an MP4 fallback) while
/// [active], loops, and follows the app-wide sound switch. It pauses when it is not the visible
/// slide, when another screen covers it, or when the app goes to the background.
class ProductVideoPlayer extends StatefulWidget {
  final Map<String, dynamic> video; // {hls, mp4, poster, width, height}
  final bool active;
  final BoxFit fit;

  const ProductVideoPlayer({super.key, required this.video, required this.active, this.fit = BoxFit.cover});

  @override
  State<ProductVideoPlayer> createState() => _ProductVideoPlayerState();
}

class _ProductVideoPlayerState extends State<ProductVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _pausedByUser = false;
  bool _appVisible = true;
  bool _routeVisible = true;

  bool get _shouldPlay => widget.active && _appVisible && _routeVisible && !_pausedByUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaSound.instance.addListener(_applyVolume);
    if (widget.active) _create();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuilds when a route is pushed on top of this one (or popped back)
    _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProductVideoPlayer old) {
    super.didUpdateWidget(old);
    if (widget.active && _controller == null && !_failed) _create();
    if (!widget.active) _pausedByUser = false;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _sync();
  }

  void _create({bool fallback = false}) {
    final url = fallback ? widget.video['mp4'] : (widget.video['hls'] ?? widget.video['mp4']);
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(
      Uri.parse('$url'),
      formatHint: fallback ? null : VideoFormat.hls,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = c;
    c.initialize().then((_) {
      if (!mounted || _controller != c) return;
      c.setLooping(true);
      c.setVolume(MediaSound.instance.volume);
      setState(() {});
      _sync();
    }).catchError((_) {
      if (!mounted || _controller != c) return;
      c.dispose();
      _controller = null;
      if (!fallback && widget.video['mp4'] != null) {
        _create(fallback: true);
      } else {
        setState(() => _failed = true);
      }
    });
  }

  void _sync() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_shouldPlay && !c.value.isPlaying) c.play();
    if (!_shouldPlay && c.value.isPlaying) c.pause();
  }

  void _applyVolume() {
    _controller?.setVolume(MediaSound.instance.volume);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MediaSound.instance.removeListener(_applyVolume);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final poster = widget.video['poster'] as String?;
    return GestureDetector(
      onTap: ready
          ? () => setState(() {
                _pausedByUser = c.value.isPlaying;
                _sync();
              })
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (poster != null) CachedNetworkImage(imageUrl: poster, fit: widget.fit, errorWidget: (_, __, ___) => const SizedBox()),
          if (ready)
            FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            ),
          if (widget.active && !ready && !_failed) const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
          if (_failed)
            Center(
              child: Text(tr(context, 'Video unavailable', 'Video ei ole saatavilla'), style: const TextStyle(color: Colors.white70)),
            ),
          if (ready && _pausedByUser) const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 72)),
          if (ready)
            Positioned(
              right: 12,
              bottom: 12,
              child: Semantics(
                button: true,
                label: MediaSound.instance.on ? tr(context, 'Mute', 'Mykistä') : tr(context, 'Sound on', 'Ääni päälle'),
                child: GestureDetector(
                  onTap: MediaSound.instance.toggle,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.black54,
                    child: Icon(MediaSound.instance.on ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
