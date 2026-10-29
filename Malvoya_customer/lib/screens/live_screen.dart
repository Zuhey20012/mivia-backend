import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/deep_links.dart';
import '../core/media_sound.dart';
import '../core/report_reasons.dart';
import '../core/sign_in.dart';
import '../services/socket_service.dart';
import '../widgets/add_to_bag_sheet.dart';
import '../widgets/app_image.dart';
import '../widgets/live_list.dart';
import 'product_detail.dart';
import 'store_detail.dart';

enum _Phase { loading, connecting, watching, ended, off, missing, failed }

/// A store's live stream: the video (LiveKit, watched only — the viewer never publishes), the chat, hearts,
/// the pinned product and every product the store shows. Lives are not recorded.
///
/// Signed-in viewers get chat, hearts and live counts over the app's Socket.io connection; guests watch, and
/// see messages and counts refreshed every 15 seconds.
class LiveScreen extends StatefulWidget {
  final int liveId;

  /// What the list already knows (title, store, cover, viewers), shown while the live loads.
  final Map<String, dynamic>? preview;

  const LiveScreen({super.key, required this.liveId, this.preview});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 15);
  static const _likeGap = Duration(milliseconds: 1100);
  static const _maxMessages = 80;
  static const _maxText = 200;

  /// WebRTC is set up once per app run, for media playback (not a call: the speaker, media volume).
  static Future<void>? _liveKitInit;

  Map<String, dynamic> _live = {};
  _Phase _phase = _Phase.loading;
  String? _errorText;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomEvents;
  lk.VideoTrack? _video;
  lk.RemoteAudioTrack? _audio;
  bool _reconnecting = false;
  int _reconnectTries = 0;
  bool _closing = false;

  int _viewers = 0;
  int _likes = 0;
  int? _pinnedId;
  final List<Map<String, dynamic>> _messages = [];

  final _chat = TextEditingController();
  final _chatFocus = FocusNode();
  bool _sending = false;
  Timer? _sendTimeout;

  final List<int> _hearts = [];
  int _heartSeq = 0;
  DateTime? _lastLikeSent;

  bool? _followed;
  bool _following = false;
  bool _socketJoined = false;
  Timer? _poll;

  int get _id => widget.liveId;
  AuthService get _auth => Provider.of<AuthService>(context, listen: false);
  ApiClient get _api => ApiClient(_auth);
  bool get _muted => !MediaSound.instance.on;
  Map<String, dynamic> get _store => (_live['store'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<Map<String, dynamic>> get _products =>
      ((_live['products'] as List?) ?? const []).whereType<Map>().map((p) => p.cast<String, dynamic>()).toList();

  Map<String, dynamic>? get _pinned {
    final id = _pinnedId;
    if (id == null) return null;
    for (final p in _products) {
      if (asInt(p['id']) == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final preview = widget.preview;
    if (preview != null) {
      _live = Map<String, dynamic>.from(preview);
      _viewers = asInt(preview['viewers']) ?? 0;
      _likes = asInt(preview['likeCount']) ?? 0;
      _pinnedId = asInt(preview['pinnedProductId']);
    }
    WidgetsBinding.instance.addObserver(this);
    MediaSound.instance.addListener(_applySound);
    CustomerSocketService().addLiveListener(_onLiveEvent);
    _start();
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    MediaSound.instance.removeListener(_applySound);
    final socket = CustomerSocketService();
    socket.removeLiveListener(_onLiveEvent);
    if (_socketJoined) socket.leaveLive(_id);
    _poll?.cancel();
    _sendTimeout?.cancel();
    _disposeRoom();
    _chat.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // No sound from a live in the background
      _audio?.disable();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _applySound();
      _joinSocket();
      _loadLive(quiet: true);
      if (!_socketJoined) _loadMessages();
    }
  }

  // ── Start, video and ending ─────────────────────────────────────────────

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.loading;
      _errorText = null;
    });
    final ok = await _loadLive();
    if (!ok || !mounted || _phase == _Phase.ended) return;
    _loadMessages();
    _joinSocket();
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
      _loadLive(quiet: true);
      // Without the live connection (guests), messages arrive with the same refresh
      if (!_socketJoined || !CustomerSocketService().isConnected) _loadMessages();
    });
    await _connectVideo();
  }

  /// Loads the live (title, store, products, counts). False when it cannot be shown.
  Future<bool> _loadLive({bool quiet = false}) async {
    final res = await _api.get('/live/$_id');
    if (!mounted) return false;
    if (res.status == 404) {
      if (quiet) {
        _end();
      } else {
        setState(() => _phase = _Phase.missing);
      }
      return false;
    }
    if (!res.ok || res.data['live'] is! Map) {
      if (!quiet) {
        setState(() {
          _phase = _Phase.failed;
          _errorText = res.errorText(context);
        });
      }
      return false;
    }
    final live = Map<String, dynamic>.from(res.data['live'] as Map);
    setState(() {
      _live = {..._live, ...live};
      if (live['viewers'] != null) _viewers = asInt(live['viewers']) ?? _viewers;
      if (live['likeCount'] != null) _likes = math.max(_likes, asInt(live['likeCount']) ?? 0);
      if (live.containsKey('pinnedProductId')) _pinnedId = asInt(live['pinnedProductId']);
      final store = live['store'];
      if (_followed == null && store is Map && store.containsKey('followedByMe')) _followed = store['followedByMe'] == true;
    });
    if (live['status'] == 'ENDED') {
      _end();
      return false;
    }
    return true;
  }

  Future<void> _loadMessages() async {
    final res = await _api.get('/live/$_id/messages');
    if (!mounted || !res.ok) return;
    final list = (res.data['messages'] as List?) ?? const [];
    _setMessages(list);
  }

  void _setMessages(List list) {
    final incoming = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    setState(() {
      _messages
        ..clear()
        ..addAll(incoming.length > _maxMessages ? incoming.sublist(incoming.length - _maxMessages) : incoming);
    });
  }

  /// Signed-in viewers join the live's room on the shared connection (chat, hearts and live counts).
  void _joinSocket() {
    final auth = _auth;
    if (!auth.isAuthenticated || _phase == _Phase.ended) return;
    final socket = CustomerSocketService();
    socket.connect(auth.accessToken ?? '');
    if (!_socketJoined) {
      _socketJoined = true;
      socket.joinLive(_id);
    }
  }

  Future<void> _connectVideo() async {
    if (_closing || _phase == _Phase.ended) return;
    if (_phase != _Phase.watching) setState(() => _phase = _Phase.connecting);
    final res = await _api.post('/live/$_id/join');
    if (!mounted || _closing || _phase == _Phase.ended) return;
    if (res.status == 503 && res.data['code'] == 'LIVE_OFF') {
      setState(() => _phase = _Phase.off);
      return;
    }
    if (res.status == 409) {
      _end();
      return;
    }
    final watch = res.data['watch'];
    if (!res.ok || watch is! Map || watch['url'] is! String || watch['token'] is! String) {
      _failed(res.errorText(context));
      return;
    }
    // Media playback (not a call): Android plays through the media stream and volume, not the earpiece.
    // The audio-session API is marked experimental in livekit_client 2.13; without it the defaults are a call's.
    await (_liveKitInit ??= lk.LiveKitClient.initialize(
      // ignore: experimental_member_use
      initialAudioSessionOptions: const lk.AudioSessionOptions.mediaPlayback(),
    ).catchError((Object _) {}));
    if (!mounted || _closing) return;

    await _disposeRoom();
    final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: true));
    final events = room.createListener();
    _room = room;
    _roomEvents = events;
    events
      ..on<lk.TrackSubscribedEvent>((e) => _onTrack(room, e.track))
      ..on<lk.TrackUnsubscribedEvent>((e) => _onTrackGone(room, e.track))
      ..on<lk.RoomReconnectingEvent>((_) {
        if (mounted && _room == room) setState(() => _reconnecting = true);
      })
      ..on<lk.RoomReconnectedEvent>((_) {
        if (mounted && _room == room) setState(() => _reconnecting = false);
      })
      ..on<lk.RoomDisconnectedEvent>((_) => _onRoomDisconnected(room));
    try {
      await room.connect(watch['url'] as String, watch['token'] as String);
    } catch (_) {
      if (_room == room) _onRoomDisconnected(room);
      return;
    }
    if (!mounted || _closing || _room != room) {
      if (_room != room) {
        await room.disconnect();
        await room.dispose();
      }
      return;
    }
    // Tracks the store published before this viewer arrived
    for (final p in room.remoteParticipants.values) {
      for (final pub in [...p.videoTrackPublications, ...p.audioTrackPublications]) {
        final t = pub.track;
        if (t != null) _onTrack(room, t);
      }
    }
    _reconnectTries = 0;
    setState(() {
      _phase = _Phase.watching;
      _reconnecting = false;
    });
  }

  void _onTrack(lk.Room room, lk.Track track) {
    if (!mounted || _room != room) return;
    if (track is lk.VideoTrack) {
      setState(() => _video = track);
    } else if (track is lk.RemoteAudioTrack) {
      _audio = track;
      _applySound();
    }
  }

  void _onTrackGone(lk.Room room, lk.Track track) {
    if (!mounted || _room != room) return;
    setState(() {
      if (identical(track, _video)) _video = null;
      if (identical(track, _audio)) _audio = null;
    });
  }

  /// The connection to the video ended without this screen asking: either the live ended, or the network
  /// dropped and LiveKit gave up. Ask the API which, and connect again (a new token) up to three times.
  Future<void> _onRoomDisconnected(lk.Room room) async {
    if (_closing || _room != room || _phase == _Phase.ended) return;
    await _disposeRoom();
    if (!mounted) return;
    setState(() => _reconnecting = true);
    final stillLive = await _loadLive(quiet: true);
    if (!mounted || _closing || _phase == _Phase.ended) return;
    if (stillLive && _reconnectTries < 3) {
      _reconnectTries++;
      await Future<void>.delayed(Duration(seconds: 2 * _reconnectTries));
      if (!mounted || _closing || _phase == _Phase.ended) return;
      await _connectVideo();
    } else if (!stillLive && _phase != _Phase.ended) {
      _failed(null);
    } else {
      _failed(tr(context, 'The connection to the live was lost.', 'Yhteys liveen katkesi.'));
    }
  }

  void _failed(String? text) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _reconnecting = false;
      _errorText = text;
    });
  }

  Future<void> _disposeRoom() async {
    final room = _room;
    final events = _roomEvents;
    _room = null;
    _roomEvents = null;
    _video = null;
    _audio = null;
    await events?.dispose();
    if (room != null) {
      try {
        await room.disconnect();
        await room.dispose();
      } catch (_) {}
    }
  }

  /// The live has ended (the store ended it, it timed out, or an admin ended it).
  void _end() {
    if (!mounted || _phase == _Phase.ended) return;
    _poll?.cancel();
    _disposeRoom();
    if (_socketJoined) {
      CustomerSocketService().leaveLive(_id);
      _socketJoined = false;
    }
    _chatFocus.unfocus();
    setState(() {
      _phase = _Phase.ended;
      _reconnecting = false;
      _hearts.clear();
    });
  }

  void _applySound() {
    final a = _audio;
    if (a != null) _muted ? a.disable() : a.enable();
    if (mounted) setState(() {});
  }

  // ── Socket events ──────────────────────────────────────────────────────

  void _onLiveEvent(String event, Map<String, dynamic> data) {
    if (!mounted) return;
    final liveId = asInt(data['liveId']);
    if (liveId != null && liveId != _id) return;
    switch (event) {
      case 'live:joined':
        if (data['ok'] == false) {
          // An ended live refuses the join; anything else is checked with the next refresh
          _loadLive(quiet: true);
          return;
        }
        setState(() {
          if (data['viewers'] != null) _viewers = asInt(data['viewers']) ?? _viewers;
          if (data['likeCount'] != null) _likes = asInt(data['likeCount']) ?? _likes;
          if (data.containsKey('pinnedProductId')) _pinnedId = asInt(data['pinnedProductId']);
        });
        if (data['messages'] is List) _setMessages(data['messages'] as List);
      case 'live:message':
        final id = data['id'];
        if (id != null && _messages.any((m) => m['id'] == id)) return;
        setState(() {
          _messages.add(data);
          if (_messages.length > _maxMessages) _messages.removeRange(0, _messages.length - _maxMessages);
        });
      case 'live:message_hidden':
        setState(() => _messages.removeWhere((m) => m['id'] == data['id']));
      case 'live:viewers':
        setState(() => _viewers = asInt(data['count']) ?? _viewers);
      case 'live:likes':
        setState(() => _likes = asInt(data['count']) ?? _likes);
      case 'live:pinned':
        setState(() => _pinnedId = asInt(data['productId']));
      case 'live:ended':
        _end();
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Asks a guest to sign in; true when signed in. Joins the live connection after signing in.
  Future<bool> _signedInFor(String en, String fi) async {
    if (_auth.isAuthenticated) return true;
    var signedIn = false;
    MSnack.show(context, tr(context, en, fi), actionLabel: tr(context, 'Sign in', 'Kirjaudu'), onAction: () async {
      signedIn = await openSignIn(context);
      if (signedIn && mounted) _joinSocket();
    });
    return signedIn;
  }

  Future<void> _send() async {
    final text = _chat.text.trim();
    if (text.isEmpty || _sending) return;
    if (!await _signedInFor('Sign in to chat', 'Kirjaudu sisään keskustellaksesi')) return;
    if (!mounted) return;
    final socket = CustomerSocketService();
    setState(() => _sending = true);
    void done() {
      _sendTimeout?.cancel();
      if (mounted) setState(() => _sending = false);
    }

    final sent = socket.sendLiveChat(_id, text, (answer) {
      if (!mounted) return;
      done();
      if (answer['ok'] == false) {
        final error = answer['error']?.toString();
        MSnack.error(context, error == null ? tr(context, 'Could not send. Try again.', 'Lähetys ei onnistunut. Yritä uudelleen.') : localizeServerMessage(context, error));
      } else {
        // Our own message comes back as live:message; clear only what was sent
        if (_chat.text.trim() == text) _chat.clear();
      }
    });
    if (!sent) {
      done();
      _joinSocket();
      MSnack.error(context, tr(context, 'Connecting to the chat. Try again in a moment.', 'Yhdistetään keskusteluun. Yritä hetken päästä uudelleen.'));
      return;
    }
    _sendTimeout?.cancel();
    _sendTimeout = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_sending) return;
      done();
      MSnack.error(context, tr(context, 'Could not send. Try again.', 'Lähetys ei onnistunut. Yritä uudelleen.'));
    });
  }

  /// A heart: shown at once; sent to the store at most about once a second (the server allows 10 per 10 s).
  Future<void> _like() async {
    if (!await _signedInFor('Sign in to send hearts', 'Kirjaudu sisään lähettääksesi sydämiä')) return;
    if (!mounted) return;
    Haptics.light();
    final now = DateTime.now();
    final last = _lastLikeSent;
    var counted = false;
    if (last == null || now.difference(last) >= _likeGap) {
      if (CustomerSocketService().sendLiveLike(_id)) {
        _lastLikeSent = now;
        counted = true;
      } else {
        _joinSocket();
      }
    }
    setState(() {
      if (counted) _likes++;
      if (!reduceMotion(context) && _hearts.length < 14) _hearts.add(++_heartSeq);
    });
  }

  Future<void> _toggleFollow() async {
    if (!await _signedInFor('Sign in to follow stores', 'Kirjaudu sisään seurataksesi kauppoja')) return;
    final storeId = asInt(_store['id']);
    if (storeId == null || _following || !mounted) return;
    final next = _followed != true;
    Haptics.light();
    setState(() {
      _followed = next;
      _following = true;
    });
    final res = next ? await _api.put('/stores/$storeId/follow') : await _api.delete('/stores/$storeId/follow');
    if (!mounted) return;
    setState(() {
      _following = false;
      if (!res.ok) _followed = !next;
    });
    if (!res.ok) {
      MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not follow. Try again.', 'Seuraaminen ei onnistunut. Yritä uudelleen.'));
    } else if (next) {
      MSnack.show(context, tr(context, 'Following. You will hear when this store goes live.', 'Seuraat kauppaa. Saat ilmoituksen, kun se aloittaa liven.'));
    }
  }

  Future<void> _share() async {
    Haptics.selection();
    final storeId = asInt(_store['id']);
    final url = _live['shareUrl']?.toString() ?? (storeId == null ? null : 'https://${DeepLinks.host}/s/$storeId');
    final name = (_store['name'] ?? '').toString();
    final title = (_live['title'] ?? '').toString();
    final text = tr(context, '$name is live on Malvoya: $title', '$name on livenä Malvoyassa: $title');
    await SharePlus.instance.share(ShareParams(text: url == null ? text : '$text\n$url'));
  }

  void _report() {
    showMSheet(
      context,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.lg, MSpace.sm, MSpace.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.xs),
              child: Text(tr(ctx, 'Report this live', 'Ilmoita livestä'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.sm),
              child: Text(
                tr(ctx, 'A person on the Malvoya team reviews every report. The store is not told who reported.',
                    'Malvoyan tiimi tarkistaa jokaisen ilmoituksen. Kaupalle ei kerrota, kuka ilmoitti.'),
                style: TextStyle(color: AppTheme.secondaryText(ctx), fontSize: MTextSize.label),
              ),
            ),
            for (final e in reportReasons.entries)
              ListTile(
                title: Text(isFinnish(ctx) ? e.value[1] : e.value[0]),
                onTap: () async {
                  Navigator.pop(ctx);
                  final res = await _api.post('/live/$_id/report', {'reason': e.key});
                  if (!mounted) return;
                  if (res.ok) {
                    MSnack.show(context, tr(context, 'Thanks — we will review it.', 'Kiitos — tarkistamme sen.'));
                  } else {
                    MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not send the report. Try again.', 'Ilmoitusta ei voitu lähettää. Yritä uudelleen.'));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProduct(Map<String, dynamic> product) async {
    final id = asInt(product['id']);
    if (id == null) return;
    _chatFocus.unfocus();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: id)));
  }

  Future<void> _addToBag(Map<String, dynamic> product) async {
    final added = await showAddToBagSheet(context, Map<String, dynamic>.from(product), store: Map<String, dynamic>.from(_store));
    if (added && mounted) showAddedToBag(context);
  }

  void _openStore() {
    if (_store['id'] == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: Map<String, dynamic>.from(_store))));
  }

  void _showProducts() {
    final products = _products;
    showMSheet(
      context,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.sm),
                child: Text(tr(ctx, 'In this live', 'Tässä livessä'), style: AppTheme.display(ctx, size: MTextSize.title)),
              ),
              if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(MSpace.xl),
                  child: Text(tr(ctx, 'The store has not added products to this live.', 'Kauppa ei ole lisännyt tuotteita tähän liveen.'),
                      style: TextStyle(color: AppTheme.secondaryText(ctx))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.lg),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: MSpace.sm),
                    itemBuilder: (_, i) {
                      final p = products[i];
                      return _ProductRow(
                        product: p,
                        pinned: asInt(p['id']) == _pinnedId,
                        onOpen: () {
                          Navigator.pop(ctx);
                          _openProduct(p);
                        },
                        onAdd: () {
                          Navigator.pop(ctx);
                          _addToBag(p);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: MPalette.night,
        resizeToAvoidBottomInset: false,
        body: switch (_phase) {
          _Phase.ended => _endedView(),
          _Phase.off => _messageView(
              Icons.videocam_off_outlined,
              tr(context, 'Live video is not switched on yet. Try again later.', 'Livevideo ei ole vielä käytössä. Yritä myöhemmin uudelleen.'),
            ),
          _Phase.missing => _messageView(Icons.search_off_rounded, tr(context, 'This live was not found.', 'Tätä liveä ei löytynyt.')),
          _ => _watchView(),
        },
      ),
    );
  }

  Widget _closeButton() => IconButton(
        tooltip: tr(context, 'Close', 'Sulje'),
        icon: const Icon(Icons.close_rounded, color: AppTheme.onMedia, shadows: [Shadow(blurRadius: 8, color: MPalette.scrim)]),
        onPressed: () => Navigator.maybePop(context),
      );

  Widget _messageView(IconData icon, String text) => SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(MSpace.x3l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: AppTheme.onMedia.withValues(alpha: 0.54), size: 56),
                    const SizedBox(height: MSpace.lg),
                    Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.onMedia.withValues(alpha: 0.75), fontSize: MTextSize.bodyL, height: 1.4)),
                  ],
                ),
              ),
            ),
            Positioned(left: MSpace.xs, top: MSpace.xs, child: _closeButton()),
          ],
        ),
      );

  Widget _backdrop() {
    final cover = _live['cover'] is String ? _live['cover'] as String : null;
    final video = _video;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null) AppImage(cover),
        if (video != null) lk.VideoTrackRenderer(video, key: ObjectKey(video), fit: lk.VideoViewFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.2, 0.5, 1],
              colors: [MPalette.mediaScrimSoft, Colors.transparent, Colors.transparent, MPalette.mediaScrim],
            ),
          ),
        ),
      ],
    );
  }

  Widget _watchView() {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bottom = keyboard > 0 ? keyboard + MSpace.sm : media.viewPadding.bottom + MSpace.md;
    final pinned = _pinned;
    final busy = _phase == _Phase.loading || _phase == _Phase.connecting || _reconnecting || (_phase == _Phase.watching && _video == null);

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _chatFocus.unfocus(),
          onDoubleTap: _phase == _Phase.watching ? _like : null,
          child: _backdrop(),
        ),
        if (busy && _phase != _Phase.failed)
          Center(
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.md),
                decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onMedia)),
                    const SizedBox(width: MSpace.md),
                    Text(
                      _reconnecting
                          ? tr(context, 'Reconnecting…', 'Yhdistetään uudelleen…')
                          : _phase == _Phase.watching
                              ? tr(context, 'Waiting for the store’s video…', 'Odotetaan kaupan videota…')
                              : tr(context, 'Joining the live…', 'Liitytään liveen…'),
                      style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_phase == _Phase.failed)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(MSpace.x3l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded, color: AppTheme.onMedia.withValues(alpha: 0.7), size: 48),
                  const SizedBox(height: MSpace.md),
                  Text(
                    _errorText ?? tr(context, 'Could not open the live. Check your connection.', 'Liveä ei voitu avata. Tarkista yhteys.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.bodyL, height: 1.4, shadows: [Shadow(blurRadius: 8, color: MPalette.ink)]),
                  ),
                  const SizedBox(height: MSpace.lg),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.onMedia, side: BorderSide(color: MPalette.white.withValues(alpha: 0.5))),
                    onPressed: () {
                      _reconnectTries = 0;
                      _live['products'] == null ? _start() : _connectVideo();
                    },
                    child: Text(tr(context, 'Try again', 'Yritä uudelleen')),
                  ),
                ],
              ),
            ),
          ),
        // Floating hearts rise from the hearts button
        for (final id in _hearts)
          Positioned(
            right: 18,
            bottom: bottom + 24,
            child: _FloatingHeart(
              key: ValueKey(id),
              seed: id,
              onDone: () {
                if (mounted) setState(() => _hearts.remove(id));
              },
            ),
          ),
        Positioned(left: 0, right: 0, top: 0, child: _topBar()),
        Positioned(
          left: MSpace.md,
          right: MSpace.md,
          bottom: bottom,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chatList(media.size.height * (keyboard > 0 ? 0.2 : 0.28)),
                    if (pinned != null) ...[
                      const SizedBox(height: MSpace.sm),
                      _pinnedCard(pinned),
                    ],
                    const SizedBox(height: MSpace.sm),
                    _input(),
                  ],
                ),
              ),
              const SizedBox(width: MSpace.sm),
              _rail(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    final store = _store;
    final name = (store['name'] ?? '').toString();
    final title = (_live['title'] ?? '').toString();
    const shadow = [Shadow(blurRadius: 8, color: MPalette.ink)];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.xs, MSpace.xs, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Semantics(
                    button: true,
                    label: tr(context, 'Open $name', 'Avaa $name'),
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: _openStore,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(3, 3, MSpace.sm, 3),
                        decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(MRadius.pill)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: AppTheme.primaryLight,
                              backgroundImage: store['logoUrl'] is String ? sizedImageProvider(context, store['logoUrl'] as String, 34) : null,
                              child: store['logoUrl'] is String ? null : const Icon(Icons.storefront_rounded, size: 18, color: AppTheme.primary),
                            ),
                            const SizedBox(width: MSpace.sm),
                            Flexible(
                              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w800, fontSize: MTextSize.bodyM)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: MSpace.sm),
                _followButton(),
                const Spacer(),
                IconButton(
                  tooltip: _muted ? tr(context, 'Sound on', 'Ääni päälle') : tr(context, 'Mute', 'Mykistä'),
                  icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: AppTheme.onMedia, shadows: shadow),
                  onPressed: () {
                    Haptics.selection();
                    MediaSound.instance.toggle();
                  },
                ),
                _closeButton(),
              ],
            ),
            const SizedBox(height: MSpace.sm),
            Row(
              children: [
                const LiveBadge(),
                const SizedBox(width: 6),
                Semantics(
                  label: tr(context, '$_viewers watching', '$_viewers katsojaa'),
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(MRadius.xs)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility_outlined, size: 14, color: AppTheme.onMedia),
                        const SizedBox(width: 4),
                        Text(compactCount(_viewers), style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: MSpace.sm),
                Expanded(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w600, fontSize: MTextSize.label, shadows: shadow)),
                ),
              ],
            ),
            const SizedBox(height: MSpace.xs),
            Text(tr(context, 'This live is not recorded.', 'Tätä liveä ei tallenneta.'),
                style: TextStyle(color: AppTheme.onMedia.withValues(alpha: 0.8), fontSize: MTextSize.caption, shadows: shadow)),
          ],
        ),
      ),
    );
  }

  Widget _followButton() {
    final followed = _followed == true;
    return Semantics(
      button: true,
      label: followed ? tr(context, 'Unfollow store', 'Lopeta seuraaminen') : tr(context, 'Follow store', 'Seuraa kauppaa'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleFollow,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: AnimatedContainer(
              duration: MMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 7),
              decoration: BoxDecoration(
                color: followed ? MPalette.night.withValues(alpha: 0.45) : AppTheme.primary,
                borderRadius: BorderRadius.circular(MRadius.pill),
                border: Border.all(color: MPalette.white.withValues(alpha: followed ? 0.6 : 0)),
              ),
              child: Text(followed ? tr(context, 'Following', 'Seurataan') : tr(context, 'Follow', 'Seuraa'),
                  style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
            ),
          ),
        ),
      ),
    );
  }

  /// Recent messages, newest at the bottom; older ones fade out towards the top and can be scrolled back to.
  Widget _chatList(double height) {
    if (_messages.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.3],
          colors: [Colors.transparent, MPalette.white],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          reverse: true,
          padding: EdgeInsets.zero,
          itemCount: _messages.length,
          itemBuilder: (_, i) => _messageBubble(_messages[_messages.length - 1 - i]),
        ),
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> m) {
    final byStore = m['byStore'] == true;
    final name = (m['name'] ?? '').toString();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: MSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.42), borderRadius: BorderRadius.circular(MRadius.sm)),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: byStore ? '$name · ${tr(context, 'Store', 'Kauppa')}  ' : '$name  ',
              style: TextStyle(color: byStore ? AppTheme.sunshine : AppTheme.onMedia.withValues(alpha: 0.75), fontWeight: FontWeight.w800),
            ),
            TextSpan(text: (m['text'] ?? '').toString()),
          ]),
          style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.label, height: 1.3),
        ),
      ),
    );
  }

  Widget _pinnedCard(Map<String, dynamic> product) {
    final images = (product['images'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final soldOut = product['inStock'] == false;
    return Semantics(
      button: true,
      label: tr(context, 'Pinned product: ${product['name'] ?? ''}. Open', 'Kiinnitetty tuote: ${product['name'] ?? ''}. Avaa'),
      child: GestureDetector(
        onTap: () => _openProduct(product),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(MSpace.sm),
          decoration: BoxDecoration(color: MPalette.white.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(MRadius.xs),
                child: SizedBox(
                  width: 44,
                  height: 54,
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
                    Text(tr(context, 'Pinned', 'Kiinnitetty'),
                        style: const TextStyle(color: MPalette.red, fontSize: MTextSize.caption, fontWeight: FontWeight.w800)),
                    Text((product['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: AppTheme.ink)),
                    MPrice.fromPricing(product['pricing'] as Map<String, dynamic>?, size: MPriceSize.sm, color: AppTheme.ink),
                  ],
                ),
              ),
              FilledButton(
                onPressed: soldOut ? null : () => _addToBag(product),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.onMedia,
                  padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                  minimumSize: const Size(0, 44),
                ),
                child: Text(soldOut ? tr(context, 'Sold out', 'Loppu') : tr(context, 'Add', 'Lisää')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input() {
    final signedIn = Provider.of<AuthService>(context).isAuthenticated;
    final enabled = _phase == _Phase.watching || _phase == _Phase.connecting;
    if (!signedIn) {
      return Semantics(
        button: true,
        child: GestureDetector(
          onTap: () async {
            if (await openSignIn(context) && mounted) {
              _joinSocket();
              setState(() {});
            }
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(MRadius.pill)),
            child: Text(tr(context, 'Sign in to chat', 'Kirjaudu sisään keskustellaksesi'),
                style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: MSpace.lg),
      decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(MRadius.pill)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chat,
              focusNode: _chatFocus,
              enabled: enabled,
              maxLength: _maxText,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              cursorColor: AppTheme.onMedia,
              style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.bodyM),
              decoration: InputDecoration(
                hintText: tr(context, 'Say something…', 'Kirjoita jotain…'),
                hintStyle: TextStyle(color: AppTheme.onMedia.withValues(alpha: 0.7)),
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Send', 'Lähetä'),
            onPressed: enabled && !_sending ? _send : null,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onMedia))
                : const Icon(Icons.send_rounded, color: AppTheme.onMedia),
          ),
        ],
      ),
    );
  }

  Widget _rail() {
    Widget action(IconData icon, String tooltip, VoidCallback onTap, {String? label, Color color = MPalette.white, Color? fill}) => Padding(
          padding: const EdgeInsets.only(top: MSpace.md),
          child: Semantics(
            button: true,
            label: tooltip,
            excludeSemantics: true,
            child: Tooltip(
              message: tooltip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: fill ?? MPalette.night.withValues(alpha: 0.45), shape: BoxShape.circle),
                      child: Icon(icon, size: 24, color: color),
                    ),
                    if (label != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(label,
                            style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6, color: MPalette.scrim)])),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

    final count = _products.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(Icons.more_horiz_rounded, tr(context, 'Report this live', 'Ilmoita livestä'), _report),
        action(Icons.reply_rounded, tr(context, 'Share', 'Jaa'), _share),
        action(Icons.shopping_bag_outlined, tr(context, 'Products in this live', 'Tämän liven tuotteet'), _showProducts,
            label: count > 0 ? '$count' : null, color: AppTheme.ink, fill: AppTheme.sunshine),
        action(Icons.favorite_rounded, tr(context, 'Send a heart', 'Lähetä sydän'), _like, label: compactCount(_likes), color: MPalette.like),
      ],
    );
  }

  Widget _endedView() {
    final products = _products;
    final storeName = (_store['name'] ?? '').toString();
    return SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.x4l + MSpace.xl, MSpace.xxl, MSpace.xxl),
            children: [
              Icon(Icons.videocam_off_outlined, color: AppTheme.onMedia.withValues(alpha: 0.6), size: 56),
              const SizedBox(height: MSpace.lg),
              Semantics(
                liveRegion: true,
                child: Text(tr(context, 'The live has ended', 'Live on päättynyt'),
                    textAlign: TextAlign.center, style: AppTheme.display(context, size: MTextSize.displayS, color: AppTheme.onMedia)),
              ),
              const SizedBox(height: MSpace.sm),
              Text(
                storeName.isEmpty
                    ? tr(context, 'Thanks for watching.', 'Kiitos, että katsoit.')
                    : tr(context, 'Thanks for watching. See more from $storeName.', 'Kiitos, että katsoit. Katso lisää: $storeName.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.onMedia.withValues(alpha: 0.75), fontSize: MTextSize.bodyM, height: 1.4),
              ),
              if (products.isNotEmpty) ...[
                const SizedBox(height: MSpace.xxl),
                Text(tr(context, 'Shown in the live', 'Livessä esitellyt'),
                    style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL)),
                const SizedBox(height: MSpace.sm),
                for (final p in products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MSpace.sm),
                    child: _ProductRow(product: p, pinned: false, onOpen: () => _openProduct(p), onAdd: () => _addToBag(p)),
                  ),
              ],
              const SizedBox(height: MSpace.xl),
              if (_store['id'] != null)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: _openStore,
                  child: Text(storeName.isEmpty ? tr(context, 'Visit the store', 'Siirry kauppaan') : tr(context, 'Visit $storeName', 'Siirry: $storeName')),
                ),
            ],
          ),
          Positioned(left: MSpace.xs, top: MSpace.xs, child: _closeButton()),
        ],
      ),
    );
  }
}

/// A product of the live: photo, name, price; tap opens the product, Add opens the add-to-bag sheet.
class _ProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool pinned;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  const _ProductRow({required this.product, required this.pinned, required this.onOpen, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final images = (product['images'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final soldOut = product['inStock'] == false;
    return Material(
      color: AppTheme.cardBackground(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(MSpace.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(MRadius.xs),
                child: SizedBox(
                  width: 52,
                  height: 64,
                  child: images.isEmpty
                      ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.checkroom_rounded, color: AppTheme.primary))
                      : AppImage(images.first),
                ),
              ),
              const SizedBox(width: MSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pinned)
                      Text(tr(context, 'Pinned', 'Kiinnitetty'),
                          style: const TextStyle(color: MPalette.red, fontSize: MTextSize.caption, fontWeight: FontWeight.w800)),
                    Text((product['name'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: AppTheme.primaryText(context))),
                    MPrice.fromPricing(product['pricing'] as Map<String, dynamic>?, size: MPriceSize.sm, color: AppTheme.primaryText(context)),
                  ],
                ),
              ),
              const SizedBox(width: MSpace.sm),
              FilledButton(
                onPressed: soldOut ? null : onAdd,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: MSpace.lg), minimumSize: const Size(0, 44)),
                child: Text(soldOut ? tr(context, 'Sold out', 'Loppu') : tr(context, 'Add', 'Lisää')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One heart rising from the hearts button with a small sideways drift, fading out in about 1.6 s.
class _FloatingHeart extends StatefulWidget {
  final int seed;
  final VoidCallback onDone;
  const _FloatingHeart({super.key, required this.seed, required this.onDone});

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward().whenComplete(widget.onDone);
  late final double _drift = (math.Random(widget.seed).nextDouble() - 0.5) * 60;
  late final double _size = 22 + math.Random(widget.seed * 7).nextDouble() * 12;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = Curves.easeOut.transform(_c.value);
            return Transform.translate(
              offset: Offset(_drift * math.sin(t * math.pi), -260 * t),
              child: Opacity(opacity: (1 - _c.value).clamp(0.0, 1.0), child: Transform.scale(scale: 0.6 + 0.4 * math.min(1, t * 3), child: child)),
            );
          },
          child: Icon(Icons.favorite_rounded, size: _size, color: MPalette.like, shadows: const [Shadow(blurRadius: 8, color: MPalette.scrim)]),
        ),
      );
}
