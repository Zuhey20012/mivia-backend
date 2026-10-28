import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delivery_location.dart';
import '../core/network_status.dart';
import '../core/media_sound.dart';
import '../core/report_reasons.dart';
import '../core/sign_in.dart';
import '../widgets/add_to_bag_sheet.dart';
import '../widgets/drop_comments_sheet.dart';
import 'product_detail.dart';
import 'sound_screen.dart';
import 'store_detail.dart';
import '../widgets/app_image.dart';

/// Shoppable short videos from stores near you. Everything shown here comes from the API:
/// real prices, real likes and views, and the reason each drop is in your feed.
class DropsFeedScreen extends StatefulWidget {
  /// False while another tab is showing, so video pauses.
  final bool isActive;

  /// When set, shows only this store's drops (opened from the store page) with a back button.
  final int? storeId;
  final String? storeName;
  final int? startDropId;

  /// When set, shows the drops that use this library sound (opened from the sound page) with a back button.
  final int? soundId;

  /// When true, shows the drops the signed-in customer saved (opened from Profile → Saved drops).
  final bool saved;

  /// The heading of a standalone list that is not a store's (a sound's title, "Saved drops").
  final String? title;

  /// Drops already loaded by the screen that opened this one (a grid), so the reel starts at once with the
  /// same list; later pages continue from [initialCursor].
  final List<Map<String, dynamic>>? initialDrops;
  final String? initialCursor;

  const DropsFeedScreen({
    super.key,
    this.isActive = true,
    this.storeId,
    this.storeName,
    this.startDropId,
    this.soundId,
    this.saved = false,
    this.title,
    this.initialDrops,
    this.initialCursor,
  });

  bool get standalone => storeId != null || soundId != null || saved;

  @override
  State<DropsFeedScreen> createState() => _DropsFeedScreenState();
}

class _DropsFeedScreenState extends State<DropsFeedScreen> with WidgetsBindingObserver {
  final _pages = PageController();
  final List<Map<String, dynamic>> _drops = [];
  final Map<int, VideoPlayerController> _videos = {};

  /// The added sound (library track, the store's own file or a voice-over) of a video drop, played next to
  /// its video by a second controller. Created, played, paused and freed together with the video.
  final Map<int, VideoPlayerController> _sounds = {};
  final Set<int> _completed = {};

  /// Saves being sent, so a quick second tap does not send a second request.
  final Set<int> _saving = {};
  bool _seedUsed = false;

  String _mode = 'foryou';
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// "Following" while signed out: the feed needs an account, so it asks to sign in.
  bool _needsSignIn = false;
  int _index = 0;
  bool get _muted => !MediaSound.instance.on;
  bool _paused = false;
  bool _routeCovered = false;

  /// A finger holds the drop down, or its options sheet is open: playback waits.
  bool _holding = false;
  DateTime? _watchStart;

  /// Where the last double-tap landed: a heart pops there (one at a time, newest wins).
  Offset? _burstAt;
  int _burstId = 0;
  Offset _lastDoubleTap = Offset.zero;

  bool get _shouldPlay => widget.isActive && !_paused && !_routeCovered && !_holding && mounted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaSound.instance.addListener(_onSoundChanged);
    NetworkStatus.instance.addListener(_onNetwork);
    _init();
  }

  void _onSoundChanged() {
    _videos.forEach((id, c) {
      final d = _dropWithId(id);
      if (c.value.isInitialized) c.setVolume(d == null ? (_muted ? 0 : 1) : _mainVolume(d));
    });
    for (final c in _sounds.values) {
      if (c.value.isInitialized) c.setVolume(_muted ? 0 : 1);
    }
    if (mounted) setState(() {});
  }

  /// Back online after the feed failed to load: try again by itself.
  void _onNetwork() {
    if (mounted && NetworkStatus.instance.online && _error != null && !_loading) _load(reset: true);
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // An old build stored a device ID for view counting; it is no longer used, so remove it
      await prefs.remove('install_id');
    } catch (_) {}
    await DeliveryLocation.instance.load();
    await _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant DropsFeedScreen old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) {
      if (widget.isActive) {
        _watchStart = DateTime.now();
        // Get the neighbours ready again for an instant swipe
        _prepareAround(_index);
      } else {
        _flushView();
        _releaseNeighbours();
      }
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _flushView();
      _videos.values.forEach((c) => c.pause());
      _sounds.values.forEach((c) => c.pause());
    } else if (state == AppLifecycleState.resumed) {
      _watchStart = DateTime.now();
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MediaSound.instance.removeListener(_onSoundChanged);
    NetworkStatus.instance.removeListener(_onNetwork);
    _flushView();
    for (final c in [..._videos.values, ..._sounds.values]) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  /// Frees the video (or photo-drop sound) and the added sound of one drop.
  void _release(int id) {
    _videos.remove(id)?.dispose();
    _sounds.remove(id)?.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────

  Future<void> _load({bool reset = false}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _needsSignIn = false;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      _loadingMore = true;
    }
    if (_mode == 'following' && !widget.standalone && !auth.isAuthenticated) {
      setState(() {
        _needsSignIn = true;
        _drops.clear();
        _loading = false;
        _loadingMore = false;
      });
      return;
    }
    final List<Map<String, dynamic>> incoming;
    final String? nextCursor;
    final seed = reset && !_seedUsed ? widget.initialDrops : null;
    if (seed != null && seed.isNotEmpty) {
      // Opened from a grid: start with the drops it already shows
      _seedUsed = true;
      incoming = seed.map((d) => Map<String, dynamic>.from(d)).toList();
      nextCursor = widget.initialCursor;
    } else {
      final feed = !widget.standalone;
      final path = widget.storeId != null
          ? '/stores/${widget.storeId}/drops'
          : widget.soundId != null
              ? '/sounds/${widget.soundId}/drops'
              : widget.saved
                  ? '/me/saved-drops'
                  : '/drops/feed';
      final res = await ApiClient(auth).get(path, query: {
        if (feed || widget.storeId != null) 'mode': _mode,
        'limit': '8',
        if (!reset && _cursor != null) 'cursor': _cursor!,
        ...DeliveryLocation.instance.query,
      });
      if (!mounted) return;

      if (!res.ok) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (reset && res.status == 401 && _mode == 'following' && feed) {
            _needsSignIn = true;
          } else if (reset) {
            _error = res.errorText(context);
          }
        });
        return;
      }
      incoming = ((res.data['drops'] as List?) ?? []).whereType<Map>().map((d) => Map<String, dynamic>.from(d)).toList();
      nextCursor = res.data['nextCursor']?.toString();
    }
    final startId = widget.startDropId;
    if (reset && startId != null && !incoming.any((d) => asInt(d['id']) == startId)) {
      // The drop that was tapped is not on the first page: fetch it and show it first
      final one = await ApiClient(auth).get('/drops/$startId', query: DeliveryLocation.instance.query);
      if (!mounted) return;
      if (one.ok && one.data['drop'] is Map) incoming.insert(0, Map<String, dynamic>.from(one.data['drop']));
    }
    // Later pages never repeat a drop already in the list (e.g. the one shown first)
    if (!reset) incoming.removeWhere((d) => _drops.any((x) => asInt(x['id']) == asInt(d['id'])));
    setState(() {
      if (reset) {
        for (final c in [..._videos.values, ..._sounds.values]) {
          c.dispose();
        }
        _videos.clear();
        _sounds.clear();
        _drops.clear();
        _index = 0;
        if (_pages.hasClients) _pages.jumpToPage(0);
      }
      _drops.addAll(incoming);
      _cursor = nextCursor;
      _hasMore = _cursor != null;
      _loading = false;
      _loadingMore = false;
    });
    if (reset && widget.startDropId != null) {
      final start = _drops.indexWhere((d) => asInt(d['id']) == widget.startDropId);
      if (start > 0) {
        _index = start;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pages.hasClients) _pages.jumpToPage(start);
        });
      }
    }
    _prepareAround(_index);
    _watchStart ??= DateTime.now();
  }

  void _switchMode(String mode) {
    if (mode == _mode) return;
    Haptics.selection();
    _flushView();
    _mode = mode;
    _load(reset: true);
  }

  // ── Playback ────────────────────────────────────────────────────────────

  int _id(int index) => asInt(_drops[index]['id'])!;

  Map<String, dynamic>? _dropWithId(int id) {
    for (final d in _drops) {
      if (asInt(d['id']) == id) return d;
    }
    return null;
  }

  /// The added sound of a drop (`media.audio`), or null. Older API versions sent it for photo drops only.
  Map<String, dynamic>? _audioOf(Map<String, dynamic> drop) {
    final a = (drop['media'] as Map?)?['audio'];
    if (a is! Map || a['url'] is! String) return null;
    return a.cast<String, dynamic>();
  }

  /// The sound track of a photo drop (null for videos and for silent photos).
  String? _soundUrl(Map<String, dynamic> drop) => drop['kind'] == 'VIDEO' ? null : _audioOf(drop)?['url'] as String?;

  /// The sound added to a video drop, played by a second controller next to the video (null when none).
  String? _addedSoundUrl(Map<String, dynamic> drop) => drop['kind'] == 'VIDEO' ? (_audioOf(drop)?['url'] as String?) : null;

  /// The volume of a drop's main controller (its video, or a photo drop's sound) with the sound switch:
  /// a video with an added sound plays its own sound quietly underneath (MIX) or not at all (REPLACE).
  double _mainVolume(Map<String, dynamic> drop) {
    if (_muted) return 0;
    if (_addedSoundUrl(drop) == null) return 1;
    return _audioOf(drop)?['mode'] == 'REPLACE' ? 0 : 0.3;
  }

  /// Which part of a video plays (`media.trim`), or null for the whole video.
  ({Duration start, Duration end})? _trimOf(Map<String, dynamic> drop) {
    if (drop['kind'] != 'VIDEO') return null;
    final t = (drop['media'] as Map?)?['trim'];
    if (t is! Map) return null;
    final start = t['startSec'], end = t['endSec'];
    if (start is! num || end is! num || end <= start) return null;
    return (
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
    );
  }

  /// The photos of a photo drop in order (older API versions sent only one, as `image`).
  List<String> _photosOf(Map<String, dynamic> drop) {
    final media = (drop['media'] as Map?) ?? {};
    final list = (media['images'] as List?)?.whereType<String>().toList() ?? const <String>[];
    if (list.isNotEmpty) return list;
    return [if (media['image'] is String) media['image'] as String];
  }

  /// Keeps the current, previous and next videos (and their sounds, and photo-drop sound tracks) ready; frees the rest.
  void _prepareAround(int index) {
    if (_drops.isEmpty) return;
    final keep = <int>{};
    for (final i in [index, index + 1, index - 1]) {
      if (i < 0 || i >= _drops.length) continue;
      final d = _drops[i];
      if (d['kind'] != 'VIDEO' && _soundUrl(d) == null) continue;
      final id = _id(i);
      keep.add(id);
      if (!_videos.containsKey(id)) _createController(id, d);
      final added = _addedSoundUrl(d);
      if (added != null && !_sounds.containsKey(id)) _createSound(id, added);
    }
    for (final id in {..._videos.keys, ..._sounds.keys}.where((k) => !keep.contains(k)).toList()) {
      _release(id);
    }
    _syncPlayback();
  }

  /// While another tab is showing, only the current video stays loaded (paused), to save memory.
  void _releaseNeighbours() {
    if (_drops.isEmpty || _index >= _drops.length) return;
    final current = _id(_index);
    for (final id in {..._videos.keys, ..._sounds.keys}.where((k) => k != current).toList()) {
      _release(id);
    }
  }

  void _createController(int id, Map<String, dynamic> drop, {bool fallback = false}) {
    final media = (drop['media'] as Map?) ?? {};
    final sound = _soundUrl(drop);
    final url = sound ?? (fallback ? media['mp4'] : (media['hls'] ?? media['mp4']));
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      // A photo drop's sound track is a plain MP3; videos stream as HLS with an MP4 fallback
      formatHint: sound != null || fallback ? null : VideoFormat.hls,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _videos[id] = c;
    c.initialize().then((_) async {
      if (!mounted || _videos[id] != c) return;
      c.setLooping(true);
      c.setVolume(_mainVolume(drop));
      // A trimmed video starts at the start of its window
      final trim = _trimOf(drop);
      if (trim != null && trim.start > Duration.zero && trim.start < c.value.duration) await c.seekTo(trim.start);
      if (!mounted || _videos[id] != c) return;
      c.addListener(() => _onVideoTick(id, c, drop));
      setState(() {});
      _syncPlayback();
    }).catchError((_) {
      if (!mounted || _videos[id] != c) return;
      c.dispose();
      _videos.remove(id);
      if (!fallback && _soundUrl(drop) == null) _createController(id, drop, fallback: true);
    });
  }

  /// The added sound of a video drop (MP3). It loops by itself when it is shorter than the video.
  void _createSound(int id, String url) {
    final c = VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _sounds[id] = c;
    c.initialize().then((_) {
      if (!mounted || _sounds[id] != c) return;
      c.setLooping(true);
      c.setVolume(_muted ? 0 : 1);
      _syncSound(id);
    }).catchError((_) {
      // Without its added sound the video still plays (with its own sound at the usual volume)
      if (!mounted || _sounds[id] != c) return;
      c.dispose();
      _sounds.remove(id);
    });
  }

  /// Keeps a trimmed video inside its window, notes a full view and keeps the added sound in step.
  void _onVideoTick(int id, VideoPlayerController c, Map<String, dynamic> drop) {
    final v = c.value;
    if (!v.isInitialized || v.duration == Duration.zero) return;
    final trim = _trimOf(drop);
    final start = trim == null || trim.start >= v.duration ? Duration.zero : trim.start;
    final end = trim == null || trim.end > v.duration ? v.duration : trim.end;
    if (v.position >= end - const Duration(milliseconds: 450)) _completed.add(id);
    if (trim != null && !_seekingToStart.contains(id)) {
      // Past the end of the window (or before its start, e.g. after the video looped by itself): back to the start
      final past = end < v.duration && v.position >= end;
      final before = v.position < start - const Duration(milliseconds: 300);
      if (past || before) {
        _seekingToStart.add(id);
        c.seekTo(start).whenComplete(() => _seekingToStart.remove(id));
      }
    }
    _syncSound(id);
  }

  final Set<int> _seekingToStart = {};

  /// Where the added sound should be for this video position: it starts with the (trimmed) video, restarts when
  /// the video loops and repeats by itself when it is shorter.
  Duration _soundOffset(Map<String, dynamic>? drop, Duration videoPos, Duration soundLength) {
    final start = drop == null ? Duration.zero : (_trimOf(drop)?.start ?? Duration.zero);
    var offset = videoPos - start;
    if (offset < Duration.zero) offset = Duration.zero;
    if (soundLength > Duration.zero) offset = Duration(microseconds: offset.inMicroseconds % soundLength.inMicroseconds);
    return offset;
  }

  /// Plays a video drop's added sound exactly while its video plays, and moves it back in step when the video
  /// looped, was scrubbed or stalled.
  void _syncSound(int id) {
    final v = _videos[id];
    final s = _sounds[id];
    if (s == null || !s.value.isInitialized) return;
    final playing = v != null && v.value.isInitialized && v.value.isPlaying && !v.value.isBuffering;
    if (!playing) {
      if (s.value.isPlaying) s.pause();
      return;
    }
    final expected = _soundOffset(_dropWithId(id), v.value.position, s.value.duration);
    final drift = (s.value.position - expected).abs();
    // Positions are reported about twice a second, so small differences are only reporting lag
    if (drift > const Duration(milliseconds: 900)) s.seekTo(expected);
    if (!s.value.isPlaying) s.play();
  }

  void _syncPlayback() {
    if (_drops.isEmpty) return;
    final currentId = _index < _drops.length ? _id(_index) : null;
    _videos.forEach((id, c) {
      if (!c.value.isInitialized) return;
      if (id == currentId && _shouldPlay) {
        if (!c.value.isPlaying) c.play();
      } else if (c.value.isPlaying) {
        c.pause();
      }
    });
    for (final id in _sounds.keys.toList()) {
      _syncSound(id);
    }
  }

  void _onPage(int i) {
    _flushView();
    setState(() {
      _index = i;
      _paused = false;
    });
    _watchStart = DateTime.now();
    _prepareAround(i);
    if (i >= _drops.length - 3) _load();
  }

  /// Reports how long the drop was watched. Views under a second are not sent.
  void _flushView() {
    final start = _watchStart;
    _watchStart = null;
    if (start == null || _index >= _drops.length) return;
    final watched = DateTime.now().difference(start).inMilliseconds / 1000;
    if (watched < 1) return;
    final id = _id(_index);
    final auth = Provider.of<AuthService>(context, listen: false);
    ApiClient(auth).post('/drops/$id/view', {
      'watchedSec': double.parse(watched.toStringAsFixed(1)),
      'completed': _completed.contains(id) || _drops[_index]['kind'] == 'IMAGE' && watched >= 3,
    });
  }

  void _toggleMute() {
    Haptics.selection();
    MediaSound.instance.toggle();
  }

  // ── Following and comments ──────────────────────────────────────────────

  Future<void> _toggleFollow(Map<String, dynamic> drop) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      _snack(tr(context, 'Sign in to follow stores', 'Kirjaudu sisään seurataksesi kauppoja'));
      return;
    }
    final storeId = asInt((drop['store'] as Map?)?['id']);
    if (storeId == null) return;
    final next = (drop['store'] as Map)['followedByMe'] != true;
    Haptics.light();
    setState(() => _setFollowed(storeId, next));
    final api = ApiClient(auth);
    final res = next ? await api.put('/stores/$storeId/follow') : await api.delete('/stores/$storeId/follow');
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _setFollowed(storeId, !next));
      _snack(res.errorText(context)!);
    } else if (next) {
      _snack(tr(context, 'Following. New drops from this store appear in Following.', 'Seuraat kauppaa. Sen uudet dropit näkyvät Seuratut-välilehdellä.'));
    }
  }

  /// Every drop of the same store shows the same follow state.
  void _setFollowed(int storeId, bool followed) {
    for (final d in _drops) {
      final s = d['store'];
      if (s is Map && asInt(s['id']) == storeId) s['followedByMe'] = followed;
    }
  }

  Future<void> _openComments(Map<String, dynamic> drop) async {
    await showDropComments(context, drop, onCountChanged: (n) {
      if (mounted) setState(() => drop['commentCount'] = n);
    });
  }

  Future<void> _open(Widget page) async {
    _flushView();
    setState(() => _routeCovered = true);
    _syncPlayback();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    setState(() => _routeCovered = false);
    _watchStart = DateTime.now();
    _syncPlayback();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  void _snack(String text) =>
      MSnack.show(context, text);

  Future<void> _toggleLike(Map<String, dynamic> drop, {bool onlyLike = false}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      _snack(tr(context, 'Sign in to like drops', 'Kirjaudu sisään tykätäksesi'));
      return;
    }
    final liked = drop['likedByMe'] == true;
    if (onlyLike && liked) return;
    Haptics.light();
    setState(() {
      drop['likedByMe'] = !liked;
      drop['likeCount'] = (asInt(drop['likeCount']) ?? 0) + (liked ? -1 : 1);
    });
    final api = ApiClient(auth);
    final res = liked ? await api.delete('/drops/${drop['id']}/like') : await api.post('/drops/${drop['id']}/like');
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        drop['likedByMe'] = res.data['liked'];
        drop['likeCount'] = res.data['likeCount'];
      } else {
        drop['likedByMe'] = liked;
        drop['likeCount'] = (asInt(drop['likeCount']) ?? 0) + (liked ? 1 : -1);
      }
    });
  }

  Future<void> _share(Map<String, dynamic> drop) async {
    Haptics.selection();
    final product = drop['product'] ?? {};
    final store = drop['store'] ?? {};
    await SharePlus.instance.share(ShareParams(text: '${product['name']} · ${store['name']}\n${drop['shareUrl']}'));
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/drops/${drop['id']}/share');
    if (res.ok && mounted) setState(() => drop['shareCount'] = res.data['shareCount']);
  }

  /// The API saves drops since 2.14 (feed items then carry `saveCount`); older servers show no Save.
  bool _canSave(Map<String, dynamic> drop) => drop.containsKey('saveCount') || drop.containsKey('savedByMe');

  /// Asks a signed-out viewer to sign in first; returns whether they are signed in.
  bool _signedInFor(String en, String fi) {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.isAuthenticated) return true;
    MSnack.show(context, tr(context, en, fi), actionLabel: tr(context, 'Sign in', 'Kirjaudu'), onAction: () => openSignIn(context));
    return false;
  }

  Future<void> _toggleSave(Map<String, dynamic> drop) async {
    if (!_signedInFor('Sign in to save drops', 'Kirjaudu sisään tallentaaksesi dropeja')) return;
    final id = asInt(drop['id']);
    if (id == null || _saving.contains(id)) return;
    final saved = drop['savedByMe'] == true;
    Haptics.light();
    _saving.add(id);
    setState(() {
      drop['savedByMe'] = !saved;
      drop['saveCount'] = math.max(0, (asInt(drop['saveCount']) ?? 0) + (saved ? -1 : 1));
    });
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final res = saved ? await api.delete('/drops/$id/save') : await api.put('/drops/$id/save');
    _saving.remove(id);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        drop['savedByMe'] = res.data['saved'] == true;
        if (res.data['saveCount'] != null) drop['saveCount'] = asInt(res.data['saveCount']);
      } else {
        drop['savedByMe'] = saved;
        drop['saveCount'] = math.max(0, (asInt(drop['saveCount']) ?? 0) + (saved ? 1 : -1));
      }
    });
    if (!res.ok) {
      MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not save. Try again.', 'Tallennus ei onnistunut. Yritä uudelleen.'));
    } else if (!saved) {
      _snack(tr(context, 'Saved. Find it in Profile under Saved drops.', 'Tallennettu. Löydät sen Profiilista kohdasta Tallennetut dropit.'));
    }
  }

  /// Hides the drop from this viewer's lists for good (the server remembers it); it leaves the reel at once
  /// and the snack offers Undo.
  Future<void> _notInterested(Map<String, dynamic> drop) async {
    if (!_signedInFor('Sign in to tune your drops', 'Kirjaudu sisään muokataksesi droppejasi')) return;
    final id = asInt(drop['id']);
    final at = _drops.indexOf(drop);
    if (id == null || at < 0) return;
    Haptics.selection();
    _removeAt(at);
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final res = await api.post('/drops/$id/not-interested');
    if (!mounted) return;
    if (!res.ok) {
      _insertAt(at, drop);
      MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not hide the drop. Try again.', 'Dropin piilottaminen ei onnistunut. Yritä uudelleen.'));
      return;
    }
    MSnack.show(
      context,
      tr(context, 'You will not see this drop again.', 'Et näe tätä droppia enää.'),
      actionLabel: tr(context, 'Undo', 'Kumoa'),
      onAction: () async {
        final undo = await api.delete('/drops/$id/not-interested');
        if (!mounted) return;
        if (undo.ok) {
          if (!_drops.any((d) => asInt(d['id']) == id)) _insertAt(at, drop);
        } else {
          MSnack.error(context, undo.errorText(context) ?? tr(context, 'Could not undo. Try again.', 'Kumoaminen ei onnistunut. Yritä uudelleen.'));
        }
      },
    );
  }

  /// Takes a drop out of the reel; the next one moves into its place.
  void _removeAt(int at) {
    if (at == _index) _flushView();
    final id = asInt(_drops[at]['id']);
    if (id != null) _release(id);
    setState(() {
      _drops.removeAt(at);
      if (at < _index) _index--;
      if (_index >= _drops.length) _index = math.max(0, _drops.length - 1);
      _paused = false;
    });
    _watchStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients && _drops.isNotEmpty) _pages.jumpToPage(_index);
    });
    _prepareAround(_index);
    if (_index >= _drops.length - 3) _load();
  }

  /// Puts a drop back (Undo, or the server refused to hide it) and shows it.
  void _insertAt(int at, Map<String, dynamic> drop) {
    _flushView();
    final pos = math.min(at, _drops.length);
    setState(() {
      _drops.insert(pos, drop);
      _index = pos;
      _paused = false;
    });
    _watchStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) _pages.jumpToPage(pos);
    });
    _prepareAround(pos);
  }

  /// Save, Not interested, Share and Report, from a long press or the rail's More button. Playback waits while
  /// it is open.
  Future<void> _showOptions(Map<String, dynamic> drop) async {
    setState(() => _holding = true);
    _syncPlayback();
    final saved = drop['savedByMe'] == true;
    final choice = await showMSheet<String>(
      context,
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canSave(drop))
              ListTile(
                leading: Icon(saved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
                title: Text(saved ? tr(ctx, 'Remove from saved', 'Poista tallennetuista') : tr(ctx, 'Save', 'Tallenna')),
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
            if (_canSave(drop))
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(tr(ctx, 'Not interested', 'Ei kiinnosta')),
                subtitle: Text(tr(ctx, 'Hide this drop from your lists', 'Piilota tämä droppi listoiltasi')),
                onTap: () => Navigator.pop(ctx, 'hide'),
              ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(tr(ctx, 'Share', 'Jaa')),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(tr(ctx, 'Report', 'Ilmoita')),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            const SizedBox(height: MSpace.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _holding = false);
    _syncPlayback();
    switch (choice) {
      case 'save':
        _toggleSave(drop);
      case 'hide':
        _notInterested(drop);
      case 'share':
        _share(drop);
      case 'report':
        _report(drop);
    }
  }

  Future<void> _addToBag(Map<String, dynamic> drop) async {
    final added = await showAddToBagSheet(context, Map<String, dynamic>.from(drop['product']), store: Map<String, dynamic>.from(drop['store']));
    if (added && mounted) showAddedToBag(context);
  }

  void _report(Map<String, dynamic> drop) {
    const reasons = reportReasons;
    showMSheet(context, builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.lg, MSpace.sm, MSpace.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.xs),
              child: Text(tr(context, 'Report this drop', 'Ilmoita dropista'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.sm),
              child: Text(
                tr(context, 'A person on the Malvoya team reviews every report. The store is not told who reported.',
                    'Malvoyan tiimi tarkistaa jokaisen ilmoituksen. Kaupalle ei kerrota, kuka ilmoitti.'),
                style: TextStyle(color: AppTheme.secondaryText(context), fontSize: MTextSize.label),
              ),
            ),
            for (final e in reasons.entries)
              ListTile(
                title: Text(isFinnish(context) ? e.value[1] : e.value[0]),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await ApiClient(Provider.of<AuthService>(context, listen: false))
                      .post('/drops/${drop['id']}/report', {'reason': e.key});
                  if (mounted) {
                    _snack(res.ok ? tr(context, 'Thanks — we will review it.', 'Kiitos — tarkistamme sen.') : res.errorText(context)!);
                  }
                },
              ),
          ],
        ),
      ), isScrollControlled: true, useSafeArea: false);
  }

  void _explain(Map<String, dynamic>? drop) {
    showMSheet(context, builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.xxl, MSpace.xxl, MSpace.x3l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Why am I seeing this?', 'Miksi näen tämän?'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w700)),
            if (drop?['reason'] != null) ...[
              const SizedBox(height: MSpace.sm),
              Text(drop!['reason'], style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primary)),
            ],
            const SizedBox(height: MSpace.md),
            Text(
              tr(context,
                  '"For you" ranks drops by how new they are, how people respond to them (likes, shares, full views), how close the store is to your delivery address and the store\'s rating. We do not build a profile of you. "Latest" shows the newest drops first, nothing else.',
                  '"Sinulle" järjestää dropit sen mukaan, kuinka uusia ne ovat, miten ihmiset reagoivat niihin (tykkäykset, jaot, loppuun katsotut), kuinka lähellä kauppa on toimitusosoitettasi ja kaupan arvosanan perusteella. Emme profiloi sinua. "Uusimmat" näyttää uusimmat dropit ensin.'),
              style: TextStyle(height: 1.45, color: AppTheme.secondaryText(context)),
            ),
            const SizedBox(height: MSpace.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _switchMode(_mode == 'foryou' ? 'latest' : 'foryou');
                },
                child: Text(_mode == 'foryou' ? tr(context, 'Switch to Latest', 'Vaihda: Uusimmat') : tr(context, 'Switch to For you', 'Vaihda: Sinulle')),
              ),
            ),
          ],
        ),
      ), isScrollControlled: false, useSafeArea: false);
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        color: MPalette.night,
        child: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator(color: AppTheme.onMedia))
            else if (_needsSignIn)
              _message(
                Icons.storefront_rounded,
                tr(context, 'Sign in to see stores you follow', 'Kirjaudu sisään nähdäksesi seuraamasi kaupat'),
                action: tr(context, 'Sign in / Create account', 'Kirjaudu / Luo tili'),
                onTap: () async {
                  if (await openSignIn(context) && mounted) _load(reset: true);
                },
              )
            else if (_error != null)
              _message(Icons.wifi_off_rounded, _error!, action: tr(context, 'Try again', 'Yritä uudelleen'), onTap: () => _load(reset: true))
            else if (_drops.isEmpty)
              _message(
                _mode == 'following' ? Icons.storefront_rounded : Icons.play_circle_outline_rounded,
                widget.saved
                    ? tr(context, 'No saved drops. Tap the bookmark on a drop to keep it here.', 'Ei tallennettuja droppeja. Tallenna droppi kirjanmerkillä, niin se löytyy täältä.')
                    : widget.soundId != null
                    ? tr(context, 'No drops use this sound right now.', 'Tätä ääntä ei käytetä nyt yhdessäkään dropissa.')
                    : _mode == 'following' && !widget.standalone
                    ? tr(context, 'Follow stores to see their new drops here. Tap + on a store in For you.',
                        'Seuraa kauppoja nähdäksesi niiden uudet dropit täällä. Napauta kaupan +-merkkiä Sinulle-välilehdellä.')
                    : tr(context, 'No drops yet. When stores near you post videos, they show up here.',
                        'Ei vielä droppeja. Kun lähialueen kaupat julkaisevat videoita, ne näkyvät täällä.'),
                action: tr(context, 'Refresh', 'Päivitä'),
                onTap: () => _load(reset: true),
              )
            else
              RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: PageView.builder(
                  controller: _pages,
                  scrollDirection: Axis.vertical,
                  itemCount: _drops.length,
                  onPageChanged: _onPage,
                  itemBuilder: (_, i) => _dropPage(_drops[i], i == _index),
                ),
              ),
            _topBar(),
          ],
        ),
      ),
    );
    return widget.standalone ? Scaffold(backgroundColor: MPalette.night, body: body) : body;
  }

  Widget _message(IconData icon, String text, {required String action, required VoidCallback onTap}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(MSpace.x3l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.onMedia.withValues(alpha: 0.54), size: 56),
              const SizedBox(height: MSpace.lg),
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.onMedia.withValues(alpha: 0.7), fontSize: MTextSize.bodyL, height: 1.4)),
              const SizedBox(height: MSpace.lg),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.onMedia, side: BorderSide(color: MPalette.white.withValues(alpha: 0.38))),
                onPressed: onTap,
                child: Text(action),
              ),
            ],
          ),
        ),
      );

  Widget _topBar() {
    Widget tab(String mode, String label) {
      final selected = _mode == mode;
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => _switchMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? MPalette.white : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(label,
                style: TextStyle(
                  color: selected ? AppTheme.ink : AppTheme.onMedia,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: MTextSize.bodyM,
                )),
          ),
        ),
      );
    }

    final current = _drops.isNotEmpty && _index < _drops.length ? _drops[_index] : null;
    if (widget.standalone) {
      return SafeArea(
        child: Row(
          children: [
            const BackButton(color: MPalette.white),
            Expanded(
              child: Text(widget.storeName ?? widget.title ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL, shadows: [Shadow(blurRadius: 8, color: MPalette.scrim)])),
            ),
            IconButton(
              tooltip: _muted ? tr(context, 'Sound on', 'Ääni päälle') : tr(context, 'Mute', 'Mykistä'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: AppTheme.onMedia),
              onPressed: _toggleMute,
            ),
          ],
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: MSpace.xs),
        child: Row(
          children: [
            IconButton(
              tooltip: tr(context, 'Why am I seeing this?', 'Miksi näen tämän?'),
              icon: const Icon(Icons.info_outline_rounded, color: AppTheme.onMedia),
              onPressed: () => _explain(current),
            ),
            // Three feeds in one pill; shrinks to fit narrow phones and long translations
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(21)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tab('foryou', tr(context, 'For you', 'Sinulle')),
                        tab('following', tr(context, 'Following', 'Seuratut')),
                        tab('latest', tr(context, 'Latest', 'Uusimmat')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: _muted ? tr(context, 'Sound on', 'Ääni päälle') : tr(context, 'Mute', 'Mykistä'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: AppTheme.onMedia),
              onPressed: _toggleMute,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropPage(Map<String, dynamic> drop, bool isCurrent) {
    final id = asInt(drop['id'])!;
    final media = (drop['media'] as Map?) ?? {};
    final controller = _videos[id];
    final isVideo = drop['kind'] == 'VIDEO';
    final ready = controller != null && controller.value.isInitialized;
    final photos = isVideo ? const <String>[] : _photosOf(drop);
    // Something that plays: a video, a photo drop with sound, or a slideshow of several photos
    final playable = isVideo || _soundUrl(drop) != null || photos.length > 1;
    // Inside the tab bar the navigation bar covers the bottom; opened on its own it does not
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final double bottomInset = widget.standalone ? 24.0 + safeBottom : 66.0 + math.max(12.0, safeBottom) + 16;

    return GestureDetector(
      onTap: () {
        // Tap pauses a video, a photo drop's sound and its slideshow; a single silent photo has nothing to pause
        if (!playable) return;
        setState(() => _paused = !_paused);
        _syncPlayback();
      },
      onDoubleTapDown: (d) => _lastDoubleTap = d.localPosition,
      onDoubleTap: () {
        final signedIn = Provider.of<AuthService>(context, listen: false).isAuthenticated;
        if (signedIn && !reduceMotion(context)) {
          setState(() {
            _burstAt = _lastDoubleTap;
            _burstId++;
          });
        }
        _toggleLike(drop, onlyLike: true);
      },
      // Holding a finger on the drop pauses it; letting go opens its options (playback waits until they close)
      onLongPressStart: (_) {
        Haptics.light();
        setState(() => _holding = true);
        _syncPlayback();
      },
      onLongPressEnd: (_) => _showOptions(drop),
      onLongPressCancel: () {
        if (!_holding) return;
        setState(() => _holding = false);
        _syncPlayback();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isVideo && media['poster'] != null)
            CachedNetworkImage(imageUrl: media['poster'], fit: BoxFit.cover, fadeInDuration: Duration.zero),
          // A photo drop: its photos as a slideshow (swipe sideways, or they move on by themselves while it plays)
          if (!isVideo && photos.isNotEmpty)
            _PhotoSlideshow(key: ValueKey('photos-$id'), photos: photos, playing: isCurrent && _shouldPlay),
          if (ready && isVideo)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: controller.value.size.width, height: controller.value.size.height, child: VideoPlayer(controller)),
            ),
          // Legibility gradients
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.18, 0.55, 1],
                colors: [MPalette.mediaScrimSoft, Colors.transparent, Colors.transparent, MPalette.mediaScrim],
              ),
            ),
          ),
          if (isCurrent && _paused && playable)
            Center(child: Icon(Icons.play_arrow_rounded, size: 84, color: AppTheme.onMedia.withValues(alpha: 0.7))),
          if (isCurrent && _burstAt != null)
            Positioned(
              left: _burstAt!.dx - 60,
              top: _burstAt!.dy - 60,
              child: _HeartBurst(
                key: ValueKey(_burstId),
                onDone: () {
                  if (mounted) setState(() => _burstAt = null);
                },
              ),
            ),
          // The rail shrinks on short screens instead of running under the top bar
          Positioned(
            right: 10,
            top: MediaQuery.of(context).viewPadding.top + 64,
            bottom: bottomInset + 20,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomCenter, child: _rail(drop)),
            ),
          ),
          Positioned(left: 16, right: 84, bottom: bottomInset, child: _info(drop)),
          if (ready && isVideo)
            Positioned(
              left: 0,
              right: 0,
              // The bar sits where it always did; the touch area below it makes scrubbing easier
              bottom: bottomInset - 10 - _ReelProgress.touchHeight + _ReelProgress.barHeight,
              child: _ReelProgress(controller: controller, trim: _trimOf(drop)),
            ),
        ],
      ),
    );
  }

  Widget _rail(Map<String, dynamic> drop) {
    final store = (drop['store'] as Map?)?.cast<String, dynamic>() ?? {};
    final liked = drop['likedByMe'] == true;
    final saved = drop['savedByMe'] == true;
    Widget action(IconData icon, String? label, VoidCallback onTap, {Color color = MPalette.white, String? tooltip, Object? bumpOn}) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Semantics(
            button: true,
            label: tooltip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                children: [
                  // At least 48 px wide to tap
                  SizedBox(
                    width: 48,
                    height: 44,
                    child: Bump(trigger: bumpOn, child: Icon(icon, size: 34, color: color, shadows: const [Shadow(blurRadius: 10, color: MPalette.scrim)])),
                  ),
                  if (label != null)
                    Text(label,
                        style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: MPalette.scrim)])),
                ],
              ),
            ),
          ),
        );

    return Column(
      children: [
        // The store's logo with a follow button overlapping its lower edge; the follow button has a
        // full 48 px tap area inside the stack (taps outside a Stack's bounds are not received)
        Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
          child: SizedBox(
            width: 56,
            height: 76,
            child: Stack(
            alignment: Alignment.topCenter,
            children: [
              GestureDetector(
                onTap: () => _open(StoreDetailScreen(store: store)),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: MPalette.white,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryLight,
                    backgroundImage: store['logoUrl'] != null ? sizedImageProvider(context, store['logoUrl'], 44) : null,
                    child: store['logoUrl'] == null ? const Icon(Icons.storefront_rounded, color: AppTheme.primary) : null,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Semantics(
                  button: true,
                  label: store['followedByMe'] == true ? tr(context, 'Unfollow store', 'Lopeta seuraaminen') : tr(context, 'Follow store', 'Seuraa kauppaa'),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleFollow(drop),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: store['followedByMe'] == true ? MPalette.white : AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: MPalette.white, width: 2),
                          ),
                          child: Icon(store['followedByMe'] == true ? Icons.check_rounded : Icons.add_rounded,
                              size: 18, color: store['followedByMe'] == true ? AppTheme.primary : AppTheme.onMedia),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
        action(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, _compact(drop['likeCount']), () => _toggleLike(drop),
            color: liked ? MPalette.like : MPalette.white,
            tooltip: liked ? tr(context, 'Unlike', 'Poista tykkäys') : tr(context, 'Like', 'Tykkää'),
            bumpOn: liked),
        action(Icons.chat_bubble_outline_rounded, _compact(drop['commentCount']), () => _openComments(drop), tooltip: tr(context, 'Comments', 'Kommentit')),
        if (_canSave(drop))
          action(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, _compact(drop['saveCount']), () => _toggleSave(drop),
              color: saved ? AppTheme.sunshine : MPalette.white,
              tooltip: saved ? tr(context, 'Remove from saved', 'Poista tallennetuista') : tr(context, 'Save', 'Tallenna'),
              bumpOn: saved),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Semantics(
            button: true,
            label: tr(context, 'Add to bag', 'Lisää kassiin'),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => _addToBag(drop),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.sunshine,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: MPalette.night.withValues(alpha: 0.25), blurRadius: 10)],
                    ),
                    child: const Icon(Icons.shopping_bag_outlined, size: 25, color: AppTheme.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(tr(context, 'Buy', 'Osta'),
                      style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 6, color: MPalette.scrim)])),
                ],
              ),
            ),
          ),
        ),
        action(Icons.reply_rounded, _compact(drop['shareCount']), () => _share(drop), tooltip: tr(context, 'Share', 'Jaa')),
        action(Icons.more_horiz_rounded, null, () => _showOptions(drop), tooltip: tr(context, 'More options', 'Lisää toimintoja')),
      ],
    );
  }

  String _compact(dynamic n) {
    final v = asInt(n) ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} k';
    return '$v';
  }

  /// "♪ Title · Artist" for a library sound (opens the sound's page), "♪ Sound by <store>" for the store's own.
  Widget _soundLine(Map<String, dynamic> drop, Map<String, dynamic> store) {
    const shadow = [Shadow(blurRadius: 8, color: MPalette.ink)];
    final raw = _audioOf(drop)?['sound'];
    final Map sound = raw is Map ? raw : const {};
    final soundId = asInt(sound['id']);
    final String name;
    if (soundId != null) {
      final title = (sound['title'] ?? '').toString();
      final artist = (sound['artist'] ?? '').toString();
      name = [if (title.isNotEmpty) title, if (artist.isNotEmpty) artist].join(' · ');
    } else {
      name = tr(context, 'Sound by ${store['name'] ?? 'the store'}', 'Ääni: ${store['name'] ?? 'kauppa'}');
    }
    final text = _muted ? tr(context, '$name · tap the speaker to listen', '$name · napauta kaiutinta kuunnellaksesi') : name;
    // Inside that sound's own list the line has nowhere new to go
    final tappable = soundId != null && soundId != widget.soundId;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.music_note_rounded, size: 16, color: AppTheme.onMedia, shadows: shadow),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.onMedia,
              fontSize: MTextSize.caption,
              fontWeight: tappable ? FontWeight.w700 : FontWeight.w600,
              shadows: shadow,
            ),
          ),
        ),
        if (tappable) const Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.onMedia, shadows: shadow),
      ],
    );
    if (!tappable) return Padding(padding: const EdgeInsets.only(top: MSpace.xs), child: row);
    return Semantics(
      button: true,
      label: tr(context, 'Sound: $name. Open drops with this sound', 'Ääni: $name. Avaa dropit, joissa on tämä ääni'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(SoundScreen(soundId: soundId, title: sound['title']?.toString(), artist: sound['artist']?.toString())),
        // A taller tap area than the text line
        child: Padding(padding: const EdgeInsets.symmetric(vertical: MSpace.xs), child: row),
      ),
    );
  }

  Widget _info(Map<String, dynamic> drop) {
    final store = (drop['store'] as Map?)?.cast<String, dynamic>() ?? {};
    final product = (drop['product'] as Map?)?.cast<String, dynamic>() ?? {};
    final images = (product['images'] as List?)?.cast<String>() ?? const [];
    final eta = etaWindow(store);
    const shadow = [Shadow(blurRadius: 8, color: MPalette.ink)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (drop['reason'] != null)
          GestureDetector(
            onTap: () => _explain(drop),
            child: Container(
              margin: const EdgeInsets.only(bottom: MSpace.sm),
              padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: MSpace.xs),
              decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.38), borderRadius: BorderRadius.circular(14)),
              child: Text(drop['reason'], style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w600)),
            ),
          ),
        Row(
          children: [
            Flexible(
              child: Text(store['name'] ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL, shadows: shadow)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(border: Border.all(color: MPalette.white.withValues(alpha: 0.54)), borderRadius: BorderRadius.circular(6)),
              child: Text(
                store['sellerType'] == 'PRIVATE' ? tr(context, 'Private seller', 'Yksityinen') : tr(context, 'Business', 'Yritys'),
                style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (_audioOf(drop) != null) _soundLine(drop, store),
        if ((drop['caption'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(drop['caption'], maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.bodyM, height: 1.35, shadows: shadow)),
          ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _open(ProductDetailScreen(productId: asInt(product['id'])!)),
          child: Container(
            padding: const EdgeInsets.all(MSpace.sm),
            decoration: BoxDecoration(color: MPalette.white.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(AppTheme.radiusMd + 2)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(MRadius.sm),
                  child: SizedBox(
                    width: 48,
                    height: 58,
                    child: images.isEmpty
                        ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.checkroom_rounded, color: AppTheme.primary))
                        : AppImage(images.first),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(product['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: AppTheme.ink)),
                      MPrice.fromPricing(product['pricing'] as Map<String, dynamic>?, size: MPriceSize.sm, color: AppTheme.ink),
                      Text(
                        [
                          if (eta != null) eta,
                          if (store['deliveryFeeCents'] != null) '${tr(context, 'delivery', 'toimitus')} ${euro(context, store['deliveryFeeCents'])}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.inkSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: product['inStock'] == false ? null : () => _addToBag(drop),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onMedia,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(product['inStock'] == false ? tr(context, 'Sold out', 'Loppu') : tr(context, 'Add', 'Lisää')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The heart that pops where a drop was double-tapped: grows, settles and fades in under a second.
class _HeartBurst extends StatefulWidget {
  final VoidCallback onDone;
  const _HeartBurst({super.key, required this.onDone});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 760))
    ..forward().whenComplete(widget.onDone);
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 20),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
  ]).animate(_c);
  late final _fade = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 65),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 35),
  ]).animate(_c);
  late final _rise = Tween(begin: Offset.zero, end: const Offset(0, -0.25)).animate(CurvedAnimation(parent: _c, curve: const Interval(0.6, 1, curve: Curves.easeIn)));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SlideTransition(
          position: _rise,
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: SizedBox(
                width: 120,
                height: 120,
                child: Icon(Icons.favorite_rounded, size: 108, color: MPalette.like, shadows: [Shadow(blurRadius: 18, color: MPalette.night.withValues(alpha: 0.38))]),
              ),
            ),
          ),
        ),
      );
}

/// The photos of a photo drop: full screen, one after another. While the drop plays, the next photo comes every
/// 3.5 seconds (looping); the viewer can also swipe sideways. Dots show where you are when there are several.
class _PhotoSlideshow extends StatefulWidget {
  final List<String> photos;
  final bool playing;
  const _PhotoSlideshow({super.key, required this.photos, required this.playing});

  @override
  State<_PhotoSlideshow> createState() => _PhotoSlideshowState();
}

class _PhotoSlideshowState extends State<_PhotoSlideshow> {
  static const _interval = Duration(milliseconds: 3500);
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PhotoSlideshow old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.playing || widget.photos.length < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_pages.hasClients) return;
      final next = (_index + 1) % widget.photos.length;
      if (next == 0 || reduceMotion(context)) {
        _pages.jumpToPage(next);
      } else {
        _pages.animateToPage(next, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pages,
          itemCount: photos.length,
          onPageChanged: (i) {
            setState(() => _index = i);
            _sync(); // a swipe restarts the timer, so the photo the viewer chose stays on screen
          },
          itemBuilder: (_, i) => CachedNetworkImage(imageUrl: photos[i], fit: BoxFit.cover, fadeInDuration: Duration.zero),
        ),
        if (photos.length > 1)
          Positioned(
            top: MediaQuery.of(context).viewPadding.top + 64,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Semantics(
                label: tr(context, 'Photo ${_index + 1} of ${photos.length}', 'Kuva ${_index + 1}/${photos.length}'),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < photos.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.onMedia.withValues(alpha: i == _index ? 0.95 : 0.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The progress bar of a video drop. For a trimmed drop it covers only the part that plays; dragging or
/// tapping along it moves the video within that part.
class _ReelProgress extends StatelessWidget {
  static const double barHeight = 3;
  static const double touchHeight = 20;

  final VideoPlayerController controller;
  final ({Duration start, Duration end})? trim;
  const _ReelProgress({required this.controller, this.trim});

  ({Duration start, Duration length}) _window(Duration duration) {
    final t = trim;
    final start = t == null || t.start >= duration ? Duration.zero : t.start;
    final end = t == null || t.end > duration || t.end <= start ? duration : t.end;
    return (start: start, length: end - start);
  }

  void _seek(double dx, double width) {
    final duration = controller.value.duration;
    if (width <= 0 || duration <= Duration.zero) return;
    final w = _window(duration);
    final f = (dx / width).clamp(0.0, 1.0);
    controller.seekTo(w.start + Duration(microseconds: (w.length.inMicroseconds * f).round()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Semantics(
        label: tr(context, 'Video progress', 'Videon eteneminen'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _seek(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) => _seek(d.localPosition.dx, box.maxWidth),
          child: SizedBox(
            height: touchHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, v, _) {
                  var played = 0.0;
                  if (v.isInitialized && v.duration > Duration.zero) {
                    final w = _window(v.duration);
                    if (w.length > Duration.zero) {
                      played = ((v.position - w.start).inMicroseconds / w.length.inMicroseconds).clamp(0.0, 1.0);
                    }
                  }
                  return Container(
                    height: barHeight,
                    color: MPalette.white.withValues(alpha: 0.14),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(widthFactor: played, child: Container(color: AppTheme.sunshine)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
