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

  const DropsFeedScreen({super.key, this.isActive = true, this.storeId, this.storeName, this.startDropId});

  bool get standalone => storeId != null;

  @override
  State<DropsFeedScreen> createState() => _DropsFeedScreenState();
}

class _DropsFeedScreenState extends State<DropsFeedScreen> with WidgetsBindingObserver {
  final _pages = PageController();
  final List<Map<String, dynamic>> _drops = [];
  final Map<int, VideoPlayerController> _videos = {};
  final Set<int> _completed = {};

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
  DateTime? _watchStart;

  /// Where the last double-tap landed: a heart pops there (one at a time, newest wins).
  Offset? _burstAt;
  int _burstId = 0;
  Offset _lastDoubleTap = Offset.zero;

  bool get _shouldPlay => widget.isActive && !_paused && !_routeCovered && mounted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaSound.instance.addListener(_onSoundChanged);
    NetworkStatus.instance.addListener(_onNetwork);
    _init();
  }

  void _onSoundChanged() {
    for (final c in _videos.values) {
      c.setVolume(_muted ? 0 : 1);
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
    for (final c in _videos.values) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
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
    final res = await ApiClient(auth).get(widget.standalone ? '/stores/${widget.storeId}/drops' : '/drops/feed', query: {
      'mode': _mode,
      'limit': '8',
      if (!reset && _cursor != null) 'cursor': _cursor!,
      ...DeliveryLocation.instance.query,
    });
    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset && res.status == 401 && _mode == 'following') {
          _needsSignIn = true;
        } else if (reset) {
          _error = res.errorText(context);
        }
      });
      return;
    }
    final incoming = ((res.data['drops'] as List?) ?? []).whereType<Map>().map((d) => Map<String, dynamic>.from(d)).toList();
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
        for (final c in _videos.values) {
          c.dispose();
        }
        _videos.clear();
        _drops.clear();
        _index = 0;
        if (_pages.hasClients) _pages.jumpToPage(0);
      }
      _drops.addAll(incoming);
      _cursor = res.data['nextCursor'];
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

  /// Keeps the current, previous and next videos ready; frees the rest.
  void _prepareAround(int index) {
    if (_drops.isEmpty) return;
    final keep = <int>{};
    for (final i in [index, index + 1, index - 1]) {
      if (i < 0 || i >= _drops.length) continue;
      final d = _drops[i];
      if (d['kind'] != 'VIDEO') continue;
      final id = _id(i);
      keep.add(id);
      if (!_videos.containsKey(id)) _createController(id, d);
    }
    for (final id in _videos.keys.where((k) => !keep.contains(k)).toList()) {
      _videos.remove(id)?.dispose();
    }
    _syncPlayback();
  }

  /// While another tab is showing, only the current video stays loaded (paused), to save memory.
  void _releaseNeighbours() {
    if (_drops.isEmpty || _index >= _drops.length) return;
    final current = _id(_index);
    for (final id in _videos.keys.where((k) => k != current).toList()) {
      _videos.remove(id)?.dispose();
    }
  }

  void _createController(int id, Map<String, dynamic> drop, {bool fallback = false}) {
    final media = (drop['media'] as Map?) ?? {};
    final url = fallback ? media['mp4'] : (media['hls'] ?? media['mp4']);
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: fallback ? null : VideoFormat.hls,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _videos[id] = c;
    c.initialize().then((_) {
      if (!mounted || _videos[id] != c) return;
      c.setLooping(true);
      c.setVolume(_muted ? 0 : 1);
      c.addListener(() => _watchProgress(id, c));
      setState(() {});
      _syncPlayback();
    }).catchError((_) {
      if (!mounted || _videos[id] != c) return;
      c.dispose();
      _videos.remove(id);
      if (!fallback) _createController(id, drop, fallback: true);
    });
  }

  void _watchProgress(int id, VideoPlayerController c) {
    final v = c.value;
    if (!v.isInitialized || v.duration == Duration.zero) return;
    if (v.position >= v.duration - const Duration(milliseconds: 450)) _completed.add(id);
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
                _mode == 'following'
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
              child: Text(widget.storeName ?? '',
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
    final ready = controller != null && controller.value.isInitialized;
    // Inside the tab bar the navigation bar covers the bottom; opened on its own it does not
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final double bottomInset = widget.standalone ? 24.0 + safeBottom : 66.0 + math.max(12.0, safeBottom) + 16;

    return GestureDetector(
      onTap: () {
        if (drop['kind'] != 'VIDEO') return;
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media['poster'] != null)
            CachedNetworkImage(imageUrl: media['poster'], fit: BoxFit.cover, fadeInDuration: Duration.zero),
          if (ready)
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
          if (isCurrent && _paused && drop['kind'] == 'VIDEO')
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
          Positioned(right: 10, bottom: bottomInset + 20, child: _rail(drop)),
          Positioned(left: 16, right: 84, bottom: bottomInset, child: _info(drop)),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset - 10,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
                colors: VideoProgressColors(playedColor: AppTheme.sunshine, bufferedColor: MPalette.white.withValues(alpha: 0.24), backgroundColor: MPalette.white.withValues(alpha: 0.1)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rail(Map<String, dynamic> drop) {
    final store = (drop['store'] as Map?)?.cast<String, dynamic>() ?? {};
    final liked = drop['likedByMe'] == true;
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
        action(Icons.more_horiz_rounded, null, () => _report(drop), tooltip: tr(context, 'More', 'Lisää')),
      ],
    );
  }

  String _compact(dynamic n) {
    final v = asInt(n) ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} k';
    return '$v';
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
