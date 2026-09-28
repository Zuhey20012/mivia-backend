import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/delivery_location.dart';
import '../core/strings.dart';
import '../widgets/add_to_bag_sheet.dart';
import '../widgets/price_tag.dart';
import 'product_detail.dart';
import 'store_detail.dart';

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
  int _index = 0;
  bool _muted = false;
  bool _paused = false;
  bool _routeCovered = false;
  String? _installId;
  DateTime? _watchStart;

  bool get _shouldPlay => widget.isActive && !_paused && !_routeCovered && mounted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool('drops_muted') ?? false;
      _installId = prefs.getString('install_id');
      if (_installId == null) {
        final r = Random.secure();
        _installId = List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
        await prefs.setString('install_id', _installId!);
      }
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
      } else {
        _flushView();
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
    _flushView();
    for (final c in _videos.values) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      _loadingMore = true;
    }
    final auth = Provider.of<AuthService>(context, listen: false);
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
        if (reset) _error = res.error;
      });
      return;
    }
    final incoming = ((res.data['drops'] as List?) ?? []).map((d) => Map<String, dynamic>.from(d)).toList();
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
    HapticFeedback.selectionClick();
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
      if (!auth.isAuthenticated && _installId != null) 'installId': _installId,
    });
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
    for (final c in _videos.values) {
      c.setVolume(_muted ? 0 : 1);
    }
    SharedPreferences.getInstance().then((p) => p.setBool('drops_muted', _muted)).catchError((_) => false);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  Future<void> _toggleLike(Map<String, dynamic> drop, {bool onlyLike = false}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      _snack(tr(context, 'Sign in to like drops', 'Kirjaudu sisään tykätäksesi'));
      return;
    }
    final liked = drop['likedByMe'] == true;
    if (onlyLike && liked) return;
    HapticFeedback.lightImpact();
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
    HapticFeedback.selectionClick();
    final product = drop['product'] ?? {};
    final store = drop['store'] ?? {};
    await SharePlus.instance.share(ShareParams(text: '${product['name']} · ${store['name']}\n${drop['shareUrl']}'));
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/drops/${drop['id']}/share');
    if (res.ok && mounted) setState(() => drop['shareCount'] = res.data['shareCount']);
  }

  Future<void> _addToBag(Map<String, dynamic> drop) async {
    final added = await showAddToBagSheet(context, Map<String, dynamic>.from(drop['product']), store: Map<String, dynamic>.from(drop['store']));
    if (added && mounted) _snack(tr(context, 'Added to your bag', 'Lisätty kassiin'));
  }

  void _report(Map<String, dynamic> drop) {
    const reasons = {
      'ILLEGAL_PRODUCT': ['Illegal or dangerous product', 'Laiton tai vaarallinen tuote'],
      'COUNTERFEIT': ['Counterfeit or fake brand', 'Väärennös'],
      'SCAM': ['Scam or misleading', 'Huijaus tai harhaanjohtava'],
      'NUDITY': ['Nudity or sexual content', 'Alastomuus tai seksuaalinen sisältö'],
      'VIOLENCE': ['Violence', 'Väkivalta'],
      'HATE': ['Hate speech', 'Vihapuhe'],
      'HARASSMENT': ['Harassment', 'Häirintä'],
      'IP_INFRINGEMENT': ['Uses someone else\'s content or brand', 'Loukkaa tekijän- tai tavaramerkkioikeutta'],
      'MINOR_SAFETY': ['Child safety', 'Lasten turvallisuus'],
      'OTHER': ['Something else', 'Jokin muu'],
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(tr(context, 'Report this drop', 'Ilmoita julkaisusta'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr(context, 'A person on the Malvoya team reviews every report. The store is not told who reported.',
                    'Malvoyan tiimi tarkistaa jokaisen ilmoituksen. Kaupalle ei kerrota, kuka ilmoitti.'),
                style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 13),
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
                    _snack(res.ok ? tr(context, 'Thanks — we will review it.', 'Kiitos — tarkistamme sen.') : res.error!);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _explain(Map<String, dynamic>? drop) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Why am I seeing this?', 'Miksi näen tämän?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (drop?['reason'] != null) ...[
              const SizedBox(height: 8),
              Text(drop!['reason'], style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primary)),
            ],
            const SizedBox(height: 12),
            Text(
              tr(context,
                  '"For you" ranks drops by how new they are, how people respond to them (likes, shares, full views), how close the store is to your delivery address and the store\'s rating. We do not build a profile of you. "Latest" shows the newest drops first, nothing else.',
                  '"Sinulle" järjestää julkaisut sen mukaan, kuinka uusia ne ovat, miten ihmiset reagoivat niihin (tykkäykset, jaot, loppuun katsotut), kuinka lähellä kauppa on toimitusosoitettasi ja kaupan arvosanan perusteella. Emme profiloi sinua. "Uusimmat" näyttää uusimmat julkaisut ensin.'),
              style: TextStyle(height: 1.45, color: AppTheme.secondaryText(context)),
            ),
            const SizedBox(height: 16),
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
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_error != null)
              _message(Icons.wifi_off_rounded, _error!, action: tr(context, 'Try again', 'Yritä uudelleen'), onTap: () => _load(reset: true))
            else if (_drops.isEmpty)
              _message(
                Icons.play_circle_outline_rounded,
                tr(context, 'No drops yet. When stores near you post videos, they show up here.',
                    'Ei vielä julkaisuja. Kun lähialueen kaupat julkaisevat videoita, ne näkyvät täällä.'),
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
    return widget.standalone ? Scaffold(backgroundColor: Colors.black, body: body) : body;
  }

  Widget _message(IconData icon, String text, {required String action, required VoidCallback onTap}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white54, size: 56),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
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
      return GestureDetector(
        onTap: () => _switchMode(mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 16,
                    shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                  )),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: selected ? 22 : 0,
                height: 3,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ),
        ),
      );
    }

    final current = _drops.isNotEmpty && _index < _drops.length ? _drops[_index] : null;
    if (widget.standalone) {
      return SafeArea(
        child: Row(
          children: [
            const BackButton(color: Colors.white),
            Expanded(
              child: Text(widget.storeName ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
            ),
            IconButton(
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
              onPressed: _toggleMute,
            ),
          ],
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: tr(context, 'Why am I seeing this?', 'Miksi näen tämän?'),
              icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
              onPressed: () => _explain(current),
            ),
            const Spacer(),
            tab('foryou', tr(context, 'For you', 'Sinulle')),
            tab('latest', tr(context, 'Latest', 'Uusimmat')),
            const Spacer(),
            IconButton(
              tooltip: _muted ? tr(context, 'Sound on', 'Ääni päälle') : tr(context, 'Mute', 'Mykistä'),
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
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
    final bottomInset = (widget.standalone ? 24 : 84) + MediaQuery.of(context).viewPadding.bottom;

    return GestureDetector(
      onTap: () {
        if (drop['kind'] != 'VIDEO') return;
        setState(() => _paused = !_paused);
        _syncPlayback();
      },
      onDoubleTap: () => _toggleLike(drop, onlyLike: true),
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
                colors: [Color(0x66000000), Colors.transparent, Colors.transparent, Color(0xB3000000)],
              ),
            ),
          ),
          if (isCurrent && _paused && drop['kind'] == 'VIDEO')
            const Center(child: Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70)),
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
                colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rail(Map<String, dynamic> drop) {
    final store = (drop['store'] as Map?)?.cast<String, dynamic>() ?? {};
    final liked = drop['likedByMe'] == true;
    Widget action(IconData icon, String? label, VoidCallback onTap, {Color color = Colors.white, String? tooltip}) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Semantics(
            button: true,
            label: tooltip,
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                children: [
                  Icon(icon, size: 34, color: color, shadows: const [Shadow(blurRadius: 10, color: Colors.black54)]),
                  if (label != null)
                    Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
                ],
              ),
            ),
          ),
        );

    return Column(
      children: [
        GestureDetector(
          onTap: () => _open(StoreDetailScreen(store: store)),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primaryLight,
                backgroundImage: store['logoUrl'] != null ? CachedNetworkImageProvider(store['logoUrl']) : null,
                child: store['logoUrl'] == null ? const Icon(Icons.storefront_rounded, color: AppTheme.primary) : null,
              ),
            ),
          ),
        ),
        action(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, _compact(drop['likeCount']), () => _toggleLike(drop),
            color: liked ? const Color(0xFFFF4D6D) : Colors.white, tooltip: tr(context, 'Like', 'Tykkää')),
        action(Icons.shopping_bag_outlined, tr(context, 'Buy', 'Osta'), () => _addToBag(drop), tooltip: tr(context, 'Add to bag', 'Lisää kassiin')),
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
    const shadow = [Shadow(blurRadius: 8, color: Colors.black87)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (drop['reason'] != null)
          GestureDetector(
            onTap: () => _explain(drop),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
              child: Text(drop['reason'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        Row(
          children: [
            Flexible(
              child: Text(store['name'] ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, shadows: shadow)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(6)),
              child: Text(
                store['sellerType'] == 'PRIVATE' ? tr(context, 'Private seller', 'Yksityinen') : tr(context, 'Business', 'Yritys'),
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if ((drop['caption'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(drop['caption'], maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35, shadows: shadow)),
          ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _open(ProductDetailScreen(productId: asInt(product['id'])!)),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 58,
                    child: images.isEmpty
                        ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.checkroom_rounded, color: AppTheme.primary))
                        : CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(product['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                      PriceTag(pricing: product['pricing'] as Map<String, dynamic>?, size: 14, color: AppTheme.ink),
                      Text(
                        [
                          if (eta != null) eta,
                          if (store['deliveryFeeCents'] != null) '${tr(context, 'delivery', 'toimitus')} ${euro(context, store['deliveryFeeCents'])}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: product['inStock'] == false ? null : () => _addToBag(drop),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 40)),
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
