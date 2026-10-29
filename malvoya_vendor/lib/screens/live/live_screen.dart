import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';
import '../../services/socket_service.dart';
import 'live_common.dart';

enum _Phase { connecting, live, failed, ended }

/// The store's live (API 2.15): full-screen camera, LIVE badge with the time on air, viewers, likes,
/// the chat (long-press: hide a message or mute that viewer), a row of the live's products to pin
/// one, flip camera, mute microphone and End.
///
/// The camera and microphone go to LiveKit ([publish]); viewers, likes and chat arrive over the app's
/// socket (`live:*`), with `GET /live/:id` every 15 s as a fallback. A heartbeat every 30 s keeps the
/// live on; without one for 2 minutes the server ends it. The screen stays on meanwhile.
class LiveScreen extends StatefulWidget {
  final Map<String, dynamic> live;
  final LivePublish publish;
  final LocalVideoTrack video;
  final LocalAudioTrack audio;
  final CameraPosition position;
  final List<Map<String, dynamic>> products;

  const LiveScreen({
    super.key,
    required this.live,
    required this.publish,
    required this.video,
    required this.audio,
    required this.products,
    this.position = CameraPosition.front,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  static const _heartbeatEvery = Duration(seconds: 30);
  static const _pollEvery = Duration(seconds: 15);
  static const _maxMessages = 100;

  final _socket = VendorSocketService();
  final _chat = ScrollController();

  Room? _room;
  EventsListener<RoomEvent>? _roomEvents;
  _Phase _phase = _Phase.connecting;
  String? _connectError;
  bool _reconnecting = false;
  bool _connectionLost = false;

  late final int _id = asInt(widget.live['id']) ?? 0;
  late final String _title = '${widget.live['title'] ?? ''}';
  late DateTime _startedAt = DateTime.tryParse('${widget.live['startedAt'] ?? ''}')?.toLocal() ?? DateTime.now();
  late int _viewers = asInt(widget.live['viewers']) ?? 0;
  late int _likes = asInt(widget.live['likeCount']) ?? 0;
  late int? _pinned = asInt(widget.live['pinnedProductId']);
  late int _viewerPeak = asInt(widget.live['viewerPeak']) ?? 0;
  late CameraPosition _position = widget.position;
  final List<Map<String, dynamic>> _messages = [];

  bool _micMuted = false;
  bool _flipping = false;
  bool _ending = false;
  int? _pinBusy;
  int _heartbeatFailures = 0;
  String? _endedReason;
  DateTime? _endedAt;

  Timer? _heartbeat;
  Timer? _poll;
  StreamSubscription<LiveSocketEvent>? _liveSub;
  bool _socketWasConnected = false;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {});
    _liveSub = _socket.liveEvents.listen(_onLiveEvent);
    _socket.addListener(_onSocketState);
    _socketWasConnected = _socket.isConnected;
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) => _sendHeartbeat());
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
      _joinChat();
      _sendHeartbeat();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _poll?.cancel();
    _liveSub?.cancel();
    _socket.removeListener(_onSocketState);
    _chat.dispose();
    WakelockPlus.disable().catchError((_) {});
    _closeVideo();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app: catch up at once (the live may have ended while the phone was away)
    if (state == AppLifecycleState.resumed && _phase != _Phase.ended) {
      _sendHeartbeat();
      _refresh();
      _ensureSocket();
    }
  }

  // ---------------------------------------------------------------- video (LiveKit)

  Future<void> _connect() async {
    if (_phase == _Phase.ended) return;
    setState(() {
      _phase = _Phase.connecting;
      _connectError = null;
      _connectionLost = false;
    });
    await _disconnectRoom();
    // The tracks belong to this screen: they survive a reconnect and are stopped only when the live ends
    final room = Room(roomOptions: const RoomOptions(adaptiveStream: false, dynacast: true, stopLocalTrackOnUnpublish: false));
    final events = room.createListener();
    events
      ..on<RoomReconnectingEvent>((_) {
        if (mounted) setState(() => _reconnecting = true);
      })
      ..on<RoomReconnectedEvent>((_) {
        if (mounted) setState(() => _reconnecting = false);
      })
      ..on<RoomDisconnectedEvent>((e) {
        if (!mounted || _phase == _Phase.ended || !identical(_room, room)) return;
        if (e.reason == DisconnectReason.clientInitiated) return;
        setState(() {
          _reconnecting = false;
          _connectionLost = true;
        });
      });
    _room = room;
    _roomEvents = events;
    try {
      await room.connect(widget.publish.url, widget.publish.token);
      final me = room.localParticipant;
      if (me == null) throw StateError('no local participant');
      await me.publishVideoTrack(widget.video, publishOptions: const VideoPublishOptions(simulcast: true));
      await me.publishAudioTrack(widget.audio);
      if (!mounted || !identical(_room, room)) return;
      if (_phase == _Phase.ended) {
        await _disconnectRoom();
        return;
      }
      Haptics.success();
      setState(() => _phase = _Phase.live);
    } catch (e) {
      debugPrint('[Live] connect failed: $e');
      if (!mounted || !identical(_room, room)) return;
      await _disconnectRoom();
      if (!mounted || _phase == _Phase.ended) return;
      setState(() {
        _phase = _Phase.failed;
        _connectError = tr(context, 'The video could not be connected. Check your connection and try again, or end the live.',
            'Videoyhteyttä ei saatu muodostettua. Tarkista yhteys ja yritä uudelleen tai lopeta lähetys.');
      });
    }
  }

  Future<void> _disconnectRoom() async {
    final room = _room;
    final events = _roomEvents;
    _room = null;
    _roomEvents = null;
    try {
      await events?.dispose();
      if (room != null) {
        await room.disconnect();
        await room.dispose();
      }
    } catch (_) {}
  }

  /// Leaves LiveKit and releases the camera and microphone.
  Future<void> _closeVideo() async {
    await _disconnectRoom();
    for (final LocalTrack track in [widget.video, widget.audio]) {
      try {
        await track.stop();
        await track.dispose();
      } catch (_) {}
    }
  }

  Future<void> _flip() async {
    if (_flipping || _phase != _Phase.live) return;
    Haptics.selection();
    final next = _position == CameraPosition.front ? CameraPosition.back : CameraPosition.front;
    setState(() => _flipping = true);
    try {
      await widget.video.setCameraPosition(next);
      if (mounted) setState(() => _position = next);
    } catch (e) {
      if (mounted) MSnack.error(context, mediaErrorText(context, e, camera: true));
    } finally {
      if (mounted) setState(() => _flipping = false);
    }
  }

  Future<void> _toggleMic() async {
    Haptics.selection();
    final mute = !_micMuted;
    try {
      // Only disables the track, so unmuting is instant and needs no new microphone
      if (mute) {
        await widget.audio.mute(stopOnMute: false);
      } else {
        await widget.audio.unmute(stopOnMute: false);
      }
      if (mounted) setState(() => _micMuted = mute);
    } catch (e) {
      if (mounted) MSnack.error(context, mediaErrorText(context, e, camera: false));
    }
  }

  // ---------------------------------------------------------------- server state

  Future<void> _sendHeartbeat() async {
    if (_phase == _Phase.ended || _id == 0) return;
    final res = await _api.post('/live/$_id/heartbeat');
    if (!mounted || _phase == _Phase.ended) return;
    if (res.ok) {
      if (res.data['live'] is Map && res.data['live']['status'] == 'ENDED') {
        _markEnded(res.data['live']['endedReason'], live: asMap(res.data['live']));
        return;
      }
      if (_heartbeatFailures != 0) setState(() => _heartbeatFailures = 0);
      return;
    }
    if (res.status == 404 || res.status == 409 || res.status == 410) {
      // The live is over on the server (ended by the watchdog or an admin): read why
      final info = await _api.get('/live/$_id');
      if (!mounted) return;
      final live = asMap(info.data['live']);
      _markEnded(live?['endedReason'], live: live);
      return;
    }
    setState(() => _heartbeatFailures++);
  }

  Future<void> _refresh() async {
    if (_phase == _Phase.ended || _id == 0) return;
    final res = await _api.get('/live/$_id');
    if (!mounted || _phase == _Phase.ended || !res.ok) return;
    final live = asMap(res.data['live']);
    if (live == null) return;
    if (live['status'] == 'ENDED') {
      _markEnded(live['endedReason'], live: live);
      return;
    }
    setState(() {
      _viewers = asInt(live['viewers']) ?? _viewers;
      _likes = asInt(live['likeCount']) ?? _likes;
      _viewerPeak = asInt(live['viewerPeak']) ?? _viewerPeak;
      if (live.containsKey('pinnedProductId')) _pinned = asInt(live['pinnedProductId']);
      final started = DateTime.tryParse('${live['startedAt'] ?? ''}');
      if (started != null) _startedAt = started.toLocal();
    });
  }

  /// The live is over (ended here, by the watchdog or by an admin): release everything once.
  void _markEnded(Object? reason, {Map<String, dynamic>? live}) {
    if (_phase == _Phase.ended) return;
    _heartbeat?.cancel();
    _poll?.cancel();
    setState(() {
      _phase = _Phase.ended;
      _endedReason = reason?.toString() ?? live?['endedReason']?.toString();
      _endedAt = DateTime.tryParse('${live?['endedAt'] ?? ''}')?.toLocal() ?? DateTime.now();
      _viewerPeak = asInt(live?['viewerPeak']) ?? _viewerPeak;
      _likes = asInt(live?['likeCount']) ?? _likes;
      _reconnecting = false;
      _connectionLost = false;
    });
    WakelockPlus.disable().catchError((_) {});
    _closeVideo();
  }

  /// Ends the live after confirmation. True when it is over (here or already on the server).
  Future<bool> _end({bool confirmed = false}) async {
    if (_phase == _Phase.ended) return true;
    if (_ending) return false;
    if (!confirmed && !await confirmEndLive(context, title: _title)) return false;
    if (!mounted) return false;
    Haptics.medium();
    setState(() => _ending = true);
    final res = await _api.post('/live/$_id/end');
    if (!mounted) return false;
    setState(() => _ending = false);
    if (!res.ok) {
      Haptics.warning();
      MSnack.error(context, res.errorMessage);
      return false;
    }
    final live = asMap(res.data['live']);
    _markEnded(live?['endedReason'] ?? 'store', live: live);
    return true;
  }

  Future<void> _onBack() async {
    if (_phase == _Phase.ended) {
      Navigator.of(context).pop();
      return;
    }
    if (await _end() && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- socket (viewers, likes, chat)

  void _ensureSocket() {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token != null) _socket.ensureConnected(token);
  }

  void _onSocketState() {
    final connected = _socket.isConnected;
    // (Re)connected: join the live's room again, the server forgets it with the old connection
    if (connected && !_socketWasConnected && _phase != _Phase.ended) _joinChat();
    _socketWasConnected = connected;
  }

  Future<void> _joinChat() async {
    if (_id == 0 || _phase == _Phase.ended) return;
    if (!_socket.isConnected) {
      _ensureSocket();
      await _loadMessages();
      return;
    }
    final ack = await _socket.emitWithAck('live:join', _id);
    if (!mounted) return;
    if (ack == null || ack['ok'] != true) {
      await _loadMessages();
      return;
    }
    setState(() {
      _viewers = asInt(ack['viewers']) ?? _viewers;
      _likes = asInt(ack['likeCount']) ?? _likes;
      if (ack.containsKey('pinnedProductId')) _pinned = asInt(ack['pinnedProductId']);
      if (ack['messages'] is List) _replaceMessages(ack['messages'] as List);
    });
  }

  Future<void> _loadMessages() async {
    final res = await _api.get('/live/$_id/messages');
    if (!mounted || !res.ok) return;
    final list = res.data['messages'];
    if (list is List) setState(() => _replaceMessages(list));
  }

  void _replaceMessages(List list) {
    _messages
      ..clear()
      ..addAll(list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
    if (_messages.length > _maxMessages) _messages.removeRange(0, _messages.length - _maxMessages);
    _scrollChatToEnd();
  }

  void _onLiveEvent(LiveSocketEvent e) {
    if (!mounted || _phase == _Phase.ended) return;
    final forLive = asInt(e.data['liveId']);
    if (forLive != null && forLive != _id) return;
    switch (e.name) {
      case 'live:viewers':
        setState(() {
          _viewers = asInt(e.data['count']) ?? _viewers;
          if (_viewers > _viewerPeak) _viewerPeak = _viewers;
        });
      case 'live:likes':
        setState(() => _likes = asInt(e.data['count']) ?? _likes);
      case 'live:message':
        final id = e.data['id'];
        if (id != null && _messages.any((m) => m['id'] == id)) return;
        setState(() {
          _messages.add(e.data);
          if (_messages.length > _maxMessages) _messages.removeAt(0);
        });
        _scrollChatToEnd();
      case 'live:message_hidden':
        setState(() => _messages.removeWhere((m) => m['id'] == e.data['id']));
      case 'live:pinned':
        setState(() => _pinned = asInt(e.data['productId']));
      case 'live:ended':
        _markEnded(e.data['reason'] ?? 'store');
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chat.hasClients) _chat.animateTo(_chat.position.maxScrollExtent, duration: MMotion.base, curve: MMotion.standard);
    });
  }

  /// The id of the viewer who wrote [m], when the server sends it (needed to mute them).
  static Object? _authorOf(Map<String, dynamic> m) => m['userId'] ?? m['authorId'];

  Future<void> _messageActions(Map<String, dynamic> m) async {
    Haptics.selection();
    final name = '${m['name'] ?? ''}';
    final author = _authorOf(m);
    final byStore = m['byStore'] == true;
    final choice = await showMSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.sm),
            child: Text('$name: ${m['text'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: Text(tr(context, 'Hide this message', 'Piilota tämä viesti')),
            subtitle: Text(tr(context, 'It disappears for every viewer.', 'Se katoaa kaikilta katsojilta.')),
            onTap: () => Navigator.pop(ctx, 'hide'),
          ),
          if (!byStore && author != null)
            ListTile(
              leading: const Icon(Icons.voice_over_off_outlined),
              title: Text(tr(context, 'Mute this viewer', 'Mykistä tämä katsoja')),
              subtitle: Text(tr(context, '$name can no longer chat in this live.', '$name ei voi enää kirjoittaa tähän lähetykseen.')),
              onTap: () => Navigator.pop(ctx, 'ban'),
            ),
          const SizedBox(height: MSpace.sm),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'hide') {
      final ack = await _socket.emitWithAck('live:hide', {'liveId': _id, 'messageId': m['id']});
      if (!mounted) return;
      if (ack?['ok'] == true) {
        setState(() => _messages.removeWhere((x) => x['id'] == m['id']));
        MSnack.success(context, tr(context, 'Message hidden.', 'Viesti piilotettu.'));
      } else {
        MSnack.error(context, _ackError(ack));
      }
    } else if (choice == 'ban' && author != null) {
      final ack = await _socket.emitWithAck('live:ban', {'liveId': _id, 'userId': author});
      if (!mounted) return;
      if (ack?['ok'] == true) {
        MSnack.success(context, tr(context, '$name is muted in this live.', '$name on mykistetty tässä lähetyksessä.'));
      } else {
        MSnack.error(context, _ackError(ack));
      }
    }
  }

  String _ackError(Map<String, dynamic>? ack) {
    final error = ack?['error'];
    if (error is String && error.isNotEmpty) return localizeServerMessage(context, error);
    return tr(context, 'That did not go through. Check your connection and try again.', 'Toiminto ei onnistunut. Tarkista yhteys ja yritä uudelleen.');
  }

  // ---------------------------------------------------------------- pinning

  Future<void> _pin(int productId) async {
    if (_pinBusy != null) return;
    Haptics.selection();
    final unpin = _pinned == productId;
    setState(() => _pinBusy = productId);
    final res = await _api.post('/live/$_id/pin', {'productId': unpin ? null : productId});
    if (!mounted) return;
    setState(() {
      _pinBusy = null;
      if (res.ok) {
        final live = asMap(res.data['live']);
        _pinned = live != null && live.containsKey('pinnedProductId') ? asInt(live['pinnedProductId']) : (unpin ? null : productId);
      }
    });
    if (!res.ok) MSnack.error(context, res.errorMessage);
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase == _Phase.ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: MPalette.night,
        body: _phase == _Phase.ended ? _endedView() : _liveView(),
      ),
    );
  }

  Widget _liveView() {
    return Stack(children: [
      Positioned.fill(
        child: VideoTrackRenderer(widget.video, fit: VideoViewFit.cover),
      ),
      // Scrims keep the white text readable on any picture
      const Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: 160,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)])),
          ),
        ),
      ),
      const Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 360,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB3000000), Color(0x00000000)])),
          ),
        ),
      ),
      SafeArea(
        child: Column(children: [
          _topBar(),
          if (_phase == _Phase.connecting) _notice(Icons.sync_rounded, tr(context, 'Connecting the video…', 'Yhdistetään videota…')),
          if (_reconnecting) _notice(Icons.sync_problem_rounded, tr(context, 'Connection is weak. Reconnecting…', 'Yhteys on heikko. Yhdistetään uudelleen…')),
          if (_phase == _Phase.failed || _connectionLost)
            _notice(
              Icons.wifi_off_rounded,
              _connectError ?? tr(context, 'The video connection was lost. Viewers cannot see you right now.', 'Videoyhteys katkesi. Katsojat eivät näe sinua juuri nyt.'),
              action: TextButton(
                onPressed: _connect,
                style: TextButton.styleFrom(foregroundColor: MPalette.sunshine),
                child: Text(tr(context, 'Reconnect', 'Yhdistä uudelleen')),
              ),
            ),
          if (_heartbeatFailures >= 2)
            _notice(Icons.cloud_off_rounded, tr(context, 'No connection to Malvoya. The live ends if the connection stays down for 2 minutes.',
                'Ei yhteyttä Malvoyaan. Lähetys päättyy, jos yhteys on poikki 2 minuuttia.')),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _chatList()),
            _sideControls(),
          ]),
          const SizedBox(height: MSpace.sm),
          _productRow(),
          const SizedBox(height: MSpace.sm),
        ]),
      ),
    ]);
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.sm, MSpace.md, MSpace.sm),
      child: Row(children: [
        Semantics(
          label: tr(context, 'Live', 'Livenä'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _phase == _Phase.live ? MPalette.red : MPalette.nightRaised, borderRadius: MRadius.pillRadius),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr(context, 'LIVE', 'LIVE'), style: const TextStyle(color: MPalette.white, fontWeight: FontWeight.w900, fontSize: MTextSize.caption, letterSpacing: 0.8)),
              const SizedBox(width: 6),
              _LiveClock(startedAt: _startedAt),
            ]),
          ),
        ),
        const SizedBox(width: MSpace.sm),
        _pill(Icons.visibility_rounded, '$_viewers', tr(context, '$_viewers watching', '$_viewers katsojaa')),
        const SizedBox(width: MSpace.xs),
        _pill(Icons.favorite_rounded, '$_likes', tr(context, '$_likes likes', '$_likes tykkäystä')),
        const Spacer(),
        FilledButton(
          onPressed: _ending ? null : () => _end(),
          style: FilledButton.styleFrom(backgroundColor: MPalette.red, foregroundColor: MPalette.white, minimumSize: const Size(64, 44)),
          child: _ending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: MPalette.white))
              : Text(tr(context, 'End', 'Lopeta')),
        ),
      ]),
    );
  }

  Widget _pill(IconData icon, String text, String label) => Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: 6),
          decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.55), borderRadius: MRadius.pillRadius),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: MPalette.white),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(color: MPalette.white, fontWeight: FontWeight.w700, fontSize: MTextSize.caption)),
          ]),
        ),
      );

  Widget _notice(IconData icon, String text, {Widget? action}) => Container(
        margin: const EdgeInsets.fromLTRB(MSpace.md, 0, MSpace.md, MSpace.sm),
        padding: EdgeInsets.fromLTRB(MSpace.md, MSpace.sm, action == null ? MSpace.md : MSpace.xs, MSpace.sm),
        decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.8), borderRadius: MRadius.brMd),
        child: Row(children: [
          Icon(icon, size: 18, color: MPalette.sunshine),
          const SizedBox(width: MSpace.sm),
          Expanded(child: Semantics(liveRegion: true, child: Text(text, style: const TextStyle(color: MPalette.white, fontSize: MTextSize.label, height: 1.35)))),
          if (action != null) action,
        ]),
      );

  Widget _sideControls() {
    Widget button({required IconData icon, required String tooltip, required VoidCallback? onPressed, bool active = false}) => Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
          child: Material(
            color: active ? MPalette.white : MPalette.night.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon, color: active ? MPalette.night : MPalette.white),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(right: MSpace.md, left: MSpace.sm),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        button(
          icon: Icons.cameraswitch_rounded,
          tooltip: _position == CameraPosition.front ? tr(context, 'Use the back camera', 'Käytä takakameraa') : tr(context, 'Use the front camera', 'Käytä etukameraa'),
          onPressed: _flipping || _phase != _Phase.live ? null : _flip,
        ),
        button(
          icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          tooltip: _micMuted ? tr(context, 'Turn the microphone on', 'Laita mikrofoni päälle') : tr(context, 'Mute the microphone', 'Mykistä mikrofoni'),
          onPressed: _toggleMic,
          active: _micMuted,
        ),
      ]),
    );
  }

  Widget _chatList() {
    if (_messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.md, 0, 0, MSpace.sm),
        child: Text(
          tr(context, 'Viewers\' messages appear here. Long-press one to hide it or mute the viewer. This live is not recorded.',
              'Katsojien viestit näkyvät tässä. Paina viestiä pitkään piilottaaksesi sen tai mykistääksesi katsojan. Tätä lähetystä ei tallenneta.'),
          style: TextStyle(color: MPalette.white.withValues(alpha: 0.85), fontSize: MTextSize.caption, height: 1.4),
        ),
      );
    }
    return SizedBox(
      height: 220,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
          stops: [0, 0.18],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _chat,
          padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.x3l, 0, 0),
          itemCount: _messages.length,
          itemBuilder: (_, i) => _messageTile(_messages[i]),
        ),
      ),
    );
  }

  Widget _messageTile(Map<String, dynamic> m) {
    final byStore = m['byStore'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: MSpace.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: byStore ? MPalette.sunshine.withValues(alpha: 0.9) : MPalette.night.withValues(alpha: 0.5),
          borderRadius: MRadius.brSm,
          child: InkWell(
            borderRadius: MRadius.brSm,
            onLongPress: () => _messageActions(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${m['name'] ?? ''}  ', style: TextStyle(fontWeight: FontWeight.w800, color: byStore ? MPalette.night : MPalette.sunshine)),
                  TextSpan(text: '${m['text'] ?? ''}'),
                ]),
                style: TextStyle(color: byStore ? MPalette.night : MPalette.white, fontSize: MTextSize.label, height: 1.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productRow() {
    if (widget.products.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MSpace.md),
        itemCount: widget.products.length,
        separatorBuilder: (_, __) => const SizedBox(width: MSpace.sm),
        itemBuilder: (_, i) => _productChip(widget.products[i]),
      ),
    );
  }

  Widget _productChip(Map<String, dynamic> p) {
    final id = asInt(p['id']);
    if (id == null) return const SizedBox.shrink();
    final pinned = _pinned == id;
    final busy = _pinBusy == id;
    final photo = productPhoto(p);
    final name = '${p['name'] ?? ''}';
    return Semantics(
      button: true,
      selected: pinned,
      label: pinned ? tr(context, '$name, pinned. Tap to unpin.', '$name, kiinnitetty. Napauta irrottaaksesi.') : tr(context, '$name. Tap to pin for viewers.', '$name. Napauta kiinnittääksesi katsojille.'),
      excludeSemantics: true,
      child: Material(
        color: pinned ? MPalette.white : MPalette.night.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: MRadius.brMd, side: BorderSide(color: pinned ? MPalette.sunshine : Colors.transparent, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _pinBusy == null && _phase != _Phase.ended ? () => _pin(id) : null,
          child: SizedBox(
            width: 200,
            child: Row(children: [
              SizedBox(
                width: 68,
                height: 72,
                child: photo != null
                    ? CachedNetworkImage(imageUrl: sizedImageUrl(photo, 200), fit: BoxFit.cover)
                    : const ColoredBox(color: MPalette.nightRaised, child: Icon(Icons.checkroom_rounded, color: MPalette.white)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MSpace.sm),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pinned ? MPalette.night : MPalette.white, fontWeight: FontWeight.w700, fontSize: MTextSize.caption, height: 1.25)),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (busy)
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: pinned ? MPalette.night : MPalette.white))
                      else
                        Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 14, color: pinned ? MPalette.amberInk : MPalette.white),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          pinned ? tr(context, 'Pinned', 'Kiinnitetty') : (p['salePriceCents'] != null ? euro(context, p['salePriceCents'] as num?) : tr(context, 'Pin', 'Kiinnitä')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: pinned ? MPalette.night : MPalette.white, fontSize: MTextSize.caption),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _endedView() {
    final duration = (_endedAt ?? DateTime.now()).difference(_startedAt);
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(color: MPalette.white, fontSize: MTextSize.displayS, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: MPalette.white.withValues(alpha: 0.75), fontSize: MTextSize.caption)),
          ]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MSpace.xxl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          const Icon(Icons.videocam_off_rounded, color: MPalette.white, size: 48),
          const SizedBox(height: MSpace.lg),
          Text(tr(context, 'Your live has ended', 'Livelähetyksesi on päättynyt'),
              textAlign: TextAlign.center, style: const TextStyle(color: MPalette.white, fontSize: MTextSize.displayS, fontWeight: FontWeight.w800)),
          const SizedBox(height: MSpace.sm),
          Semantics(
            liveRegion: true,
            child: Text(liveEndedText(context, _endedReason), textAlign: TextAlign.center, style: TextStyle(color: MPalette.white.withValues(alpha: 0.85), height: 1.4)),
          ),
          const SizedBox(height: MSpace.x3l),
          Row(children: [
            stat(elapsedText(duration), tr(context, 'on air', 'lähetysaika')),
            stat('$_viewerPeak', tr(context, 'most viewers at once', 'eniten katsojia kerralla')),
            stat('$_likes', tr(context, 'likes', 'tykkäystä')),
          ]),
          const SizedBox(height: MSpace.lg),
          Text(tr(context, 'The live was not recorded.', 'Lähetystä ei tallennettu.'),
              textAlign: TextAlign.center, style: TextStyle(color: MPalette.white.withValues(alpha: 0.7), fontSize: MTextSize.caption)),
          const Spacer(),
          MButton(label: tr(context, 'Done', 'Valmis'), expand: true, onPressed: () => Navigator.of(context).pop(true)),
        ]),
      ),
    );
  }
}

/// "12:05" since [startedAt], ticking every second without rebuilding the whole screen.
class _LiveClock extends StatefulWidget {
  final DateTime startedAt;
  const _LiveClock({required this.startedAt});

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        elapsedText(DateTime.now().difference(widget.startedAt)),
        style: const TextStyle(color: MPalette.white, fontWeight: FontWeight.w700, fontSize: MTextSize.caption, fontFeatures: [FontFeature.tabularFigures()]),
      );
}
