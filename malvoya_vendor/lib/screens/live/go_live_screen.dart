import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';
import '../../config/theme.dart';
import '../../core/agreements.dart';
import 'live_common.dart';
import 'live_screen.dart';

/// "Go live" set-up (API 2.15): a title, 1–10 of the store's products, a camera preview (front or
/// back), the note that lives are not recorded and the rules. Start creates the live (`POST /live`)
/// and opens [LiveScreen], which publishes the camera and microphone to LiveKit.
class GoLiveScreen extends StatefulWidget {
  const GoLiveScreen({super.key});

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen> {
  static const _maxProducts = 10;

  final _title = TextEditingController();
  final _search = TextEditingController();

  List<Map<String, dynamic>> _products = [];
  bool _productsLoading = true;
  String? _productsError;

  /// Product ids in the order the store picked them (the order viewers see).
  final List<int> _selected = [];

  LocalVideoTrack? _video;
  LocalAudioTrack? _audio;
  CameraPosition _position = CameraPosition.front;
  bool _cameraBusy = false;
  String? _cameraError;

  bool _starting = false;
  String? _error;

  /// True once the tracks belong to the live screen (they are not stopped here then).
  bool _handedOver = false;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProducts();
      _startCamera();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    if (!_handedOver) {
      _release(_video);
      _release(_audio);
    }
    super.dispose();
  }

  static Future<void> _release(LocalTrack? track) async {
    if (track == null) return;
    try {
      await track.stop();
      await track.dispose();
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    setState(() {
      _productsLoading = true;
      _productsError = null;
    });
    final res = await _api.get('/stores/my/products', query: {'page': '1', 'limit': '100', 'filter': 'visible'});
    if (!mounted) return;
    setState(() {
      _productsLoading = false;
      if (res.ok && res.data['products'] is List) {
        _products = (res.data['products'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
      } else {
        _productsError = res.errorMessage;
      }
    });
  }

  /// Opens the camera for the preview. Phones often cannot open both cameras at once, so the old
  /// one is closed first when switching.
  Future<void> _startCamera() async {
    if (_cameraBusy) return;
    setState(() {
      _cameraBusy = true;
      _cameraError = null;
    });
    final old = _video;
    if (old != null) {
      setState(() => _video = null);
      await _release(old);
    }
    try {
      final track = await LocalVideoTrack.createCameraTrack(CameraCaptureOptions(cameraPosition: _position, params: VideoParametersPresets.h720_169));
      if (!mounted) {
        await _release(track);
        return;
      }
      setState(() {
        _video = track;
        _cameraBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraBusy = false;
        _cameraError = mediaErrorText(context, e, camera: true);
      });
    }
  }

  void _flip() {
    Haptics.selection();
    _position = _position == CameraPosition.front ? CameraPosition.back : CameraPosition.front;
    _startCamera();
  }

  void _toggle(int id) {
    Haptics.selection();
    setState(() {
      _error = null;
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < _maxProducts) {
        _selected.add(id);
      } else {
        MSnack.show(context, tr(context, 'You can show up to $_maxProducts products in one live.', 'Yhdessä lähetyksessä voi esitellä enintään $_maxProducts tuotetta.'));
      }
    });
  }

  String get _titleText => _title.text.trim();
  bool get _titleOk => _titleText.length >= 3 && _titleText.length <= 100;
  bool get _canStart => _titleOk && _selected.isNotEmpty && _video != null && !_starting && !_cameraBusy;

  List<Map<String, dynamic>> get _chosenProducts => [
        for (final id in _selected)
          ..._products.where((p) => asInt(p['id']) == id).take(1),
      ];

  Future<void> _start() async {
    if (!_canStart) return;
    Haptics.medium();
    FocusScope.of(context).unfocus();
    setState(() {
      _starting = true;
      _error = null;
    });

    // The microphone is asked for before the live exists, so a refusal never leaves an empty live behind
    if (_audio == null) {
      try {
        _audio = await LocalAudioTrack.create();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _starting = false;
          _error = mediaErrorText(context, e, camera: false);
        });
        return;
      }
    }
    if (!mounted) return;

    final api = _api;
    final body = {'title': _titleText, 'productIds': List<int>.from(_selected)};
    var res = await withAgreement(context, api, () => api.post('/live', body));
    if (!mounted) return;

    if (res.status == 409) {
      final handled = await _alreadyLive(api, res, body);
      if (!mounted) return;
      if (handled == null) {
        setState(() => _starting = false);
        return;
      }
      res = handled;
    }

    if (!res.ok) {
      Haptics.warning();
      setState(() {
        _starting = false;
        _error = res.agreementRequired
            ? tr(context, 'Accept the Seller Terms to go live.', 'Hyväksy myyjän ehdot, niin voit aloittaa livelähetyksen.')
            : isLiveOff(res)
                ? liveOffText(context)
                : res.errorMessage;
      });
      return;
    }
    final live = asMap(res.data['live']);
    final publish = LivePublish.from(res.data);
    if (live == null || publish == null) {
      setState(() {
        _starting = false;
        _error = tr(context, 'The live was created but the video connection details are missing. End it from the Drops tab and try again.',
            'Lähetys luotiin, mutta videoyhteyden tiedot puuttuvat. Lopeta se Drops-välilehdeltä ja yritä uudelleen.');
      });
      return;
    }
    _openLive(live, publish, _chosenProducts);
  }

  /// 409: the store already has a live on. Offers to resume it (when the server gives its publish
  /// details) or to end it and start this one. Returns the answer to continue with, or null when the
  /// store cancelled or the other live was resumed.
  Future<ApiResult?> _alreadyLive(ApiClient api, ApiResult conflict, Map<String, dynamic> body) async {
    final mine = await api.get('/stores/my/live');
    if (!mounted) return null;
    var current = mine.ok ? currentLiveOf(mine.data) : null;
    current ??= asMap(conflict.data['live']);
    if (current == null) {
      // The other live ended a moment ago (or could not be read): one more try
      if (!mine.ok) {
        setState(() => _error = mine.errorMessage);
        return null;
      }
      return api.post('/live', body);
    }
    final publish = LivePublish.from(mine.data) ?? LivePublish.from(current) ?? LivePublish.from(conflict.data);
    final title = '${current['title'] ?? ''}';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'You are already live', 'Sinulla on jo lähetys käynnissä')),
        content: Text(publish != null
            ? tr(context, '"$title" is still on. Continue it on this phone, or end it and start the new live.',
                '"$title" on yhä käynnissä. Jatka sitä tällä puhelimella tai lopeta se ja aloita uusi lähetys.')
            : tr(context, '"$title" is still on. End it to start the new live.', '"$title" on yhä käynnissä. Lopeta se, niin voit aloittaa uuden lähetyksen.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'Cancel', 'Peruuta'))),
          if (publish != null) TextButton(onPressed: () => Navigator.pop(ctx, 'resume'), child: Text(tr(context, 'Continue it', 'Jatka sitä'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'end'), child: Text(tr(context, 'End it and start', 'Lopeta ja aloita'))),
        ],
      ),
    );
    if (!mounted || choice == null) return null;
    if (choice == 'resume' && publish != null) {
      final products = (current['products'] is List)
          ? (current['products'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList()
          : [
              for (final id in ((current['productIds'] as List?) ?? const []).map(asInt).whereType<int>())
                ..._products.where((p) => asInt(p['id']) == id).take(1),
            ];
      _openLive(current, publish, products);
      return null;
    }
    final ended = await api.post('/live/${current['id']}/end');
    if (!mounted) return null;
    if (!ended.ok) {
      setState(() => _error = ended.errorMessage);
      return null;
    }
    return withAgreement(context, api, () => api.post('/live', body));
  }

  /// Hands the camera and microphone to the live screen; when the live is over, this set-up closes too
  /// (so the Drops tab refreshes only then).
  Future<void> _openLive(Map<String, dynamic> live, LivePublish publish, List<Map<String, dynamic>> products) async {
    final video = _video;
    final audio = _audio;
    if (video == null || audio == null) return;
    Haptics.success();
    _handedOver = true;
    setState(() => _starting = false);
    await Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => LiveScreen(live: live, publish: publish, video: video, audio: audio, products: products, position: _position),
    ));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Go live', 'Aloita livelähetys'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.lg),
              children: [
                _preview(),
                const SizedBox(height: MSpace.lg),
                MTextField(
                  controller: _title,
                  label: tr(context, 'Title', 'Otsikko'),
                  hint: tr(context, 'e.g. New autumn coats, try-on', 'esim. Uudet syystakit, sovitus'),
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  errorText: _titleText.isNotEmpty && !_titleOk ? tr(context, 'Use 3–100 characters.', 'Käytä 3–100 merkkiä.') : null,
                ),
                const SizedBox(height: MSpace.md),
                _productsSection(),
                const SizedBox(height: MSpace.lg),
                _rules(),
              ],
            ),
          ),
          _footer(),
        ]),
      ),
    );
  }

  Widget _preview() {
    final video = _video;
    return ClipRRect(
      borderRadius: MRadius.brLg,
      child: Container(
        height: 340,
        color: MPalette.night,
        child: Stack(children: [
          if (video != null && !_handedOver)
            Positioned.fill(child: VideoTrackRenderer(video, key: ObjectKey(video), fit: VideoViewFit.cover))
          else if (_cameraError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(MSpace.xl),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.videocam_off_rounded, color: MPalette.white, size: 36),
                  const SizedBox(height: MSpace.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(_cameraError!, textAlign: TextAlign.center, style: const TextStyle(color: MPalette.white, height: 1.4)),
                  ),
                  const SizedBox(height: MSpace.md),
                  FilledButton(onPressed: _startCamera, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
                ]),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: MPalette.white)),
          Positioned(
            right: MSpace.sm,
            top: MSpace.sm,
            child: _roundButton(
              icon: Icons.cameraswitch_rounded,
              tooltip: _position == CameraPosition.front ? tr(context, 'Use the back camera', 'Käytä takakameraa') : tr(context, 'Use the front camera', 'Käytä etukameraa'),
              onPressed: _cameraBusy || _starting ? null : _flip,
            ),
          ),
          Positioned(
            left: MSpace.sm,
            bottom: MSpace.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.xs),
              decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.6), borderRadius: MRadius.pillRadius),
              child: Text(tr(context, 'Preview — not live yet', 'Esikatselu – ei vielä lähetyksessä'),
                  style: const TextStyle(color: MPalette.white, fontSize: MTextSize.caption, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _roundButton({required IconData icon, required String tooltip, required VoidCallback? onPressed}) => Material(
        color: MPalette.night.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon, color: MPalette.white)),
      );

  Widget _productsSection() {
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty ? _products : _products.where((p) => '${p['name'] ?? ''}'.toLowerCase().contains(q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(tr(context, 'Products to show', 'Esiteltävät tuotteet'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.title))),
        Text('${_selected.length}/$_maxProducts', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
      ]),
      const SizedBox(height: MSpace.xs),
      Text(tr(context, 'Pick 1–10 products. Viewers can buy them during the live, and you can pin one at a time.',
              'Valitse 1–10 tuotetta. Katsojat voivat ostaa niitä lähetyksen aikana, ja voit kiinnittää yhden kerrallaan.'),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.bodyM, height: 1.4)),
      const SizedBox(height: MSpace.sm),
      if (_productsLoading)
        const Padding(padding: EdgeInsets.all(MSpace.xl), child: Center(child: CircularProgressIndicator()))
      else if (_productsError != null && _products.isEmpty)
        MStateMessage.error(scrollable: false, message: _productsError, onRetry: _loadProducts, top: 8)
      else if (_products.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: MSpace.md),
          child: Text(
            tr(context, 'You have no products on sale yet. Publish a product first, then go live.',
                'Sinulla ei ole vielä myynnissä olevia tuotteita. Julkaise ensin tuote ja aloita sitten lähetys.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
        )
      else ...[
        if (_products.length > 8) ...[
          MTextField(controller: _search, hint: tr(context, 'Search your products', 'Hae tuotteistasi'), prefixIcon: Icons.search_rounded),
          const SizedBox(height: MSpace.sm),
        ],
        for (final p in shown) _productTile(p),
      ],
    ]);
  }

  Widget _productTile(Map<String, dynamic> p) {
    final id = asInt(p['id']);
    if (id == null) return const SizedBox.shrink();
    final index = _selected.indexOf(id);
    final selected = index >= 0;
    final soldOut = p['inStock'] == false || (p['stockQuantity'] is num && (p['stockQuantity'] as num) <= 0);
    final photo = productPhoto(p);
    final price = p['salePriceCents'];
    return Padding(
      padding: const EdgeInsets.only(bottom: MSpace.sm),
      child: Material(
        color: selected ? AppTheme.primaryLight : AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: MRadius.brMd,
          side: BorderSide(color: selected ? AppTheme.primary : AppTheme.divider, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _toggle(id),
          child: Semantics(
            selected: selected,
            button: true,
            child: Padding(
              padding: const EdgeInsets.all(MSpace.sm),
              child: Row(children: [
                ClipRRect(
                  borderRadius: MRadius.brXs,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: photo != null
                        ? CachedNetworkImage(imageUrl: sizedImageUrl(photo, 160), fit: BoxFit.cover)
                        : Container(color: AppTheme.sand, child: const Icon(Icons.checkroom_rounded, color: AppTheme.textSecondary)),
                  ),
                ),
                const SizedBox(width: MSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (price != null) euro(context, price as num?),
                        if (soldOut) tr(context, 'Sold out', 'Loppuunmyyty'),
                      ].join(' · '),
                      style: TextStyle(color: soldOut ? AppTheme.danger : AppTheme.textSecondary, fontSize: MTextSize.caption),
                    ),
                  ]),
                ),
                const SizedBox(width: MSpace.sm),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider, width: 2),
                  ),
                  child: selected
                      ? Text('${index + 1}', style: const TextStyle(color: AppTheme.onPrimary, fontWeight: FontWeight.w800, fontSize: MTextSize.caption))
                      : null,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rules() {
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: AppTheme.primary)),
            const SizedBox(width: MSpace.sm),
            Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textPrimary, height: 1.4, fontSize: MTextSize.bodyM))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: AppTheme.sand, borderRadius: MRadius.brMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.videocam_off_outlined, size: 20, color: AppTheme.textPrimary),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: Text(tr(context, 'This live is not recorded', 'Tätä lähetystä ei tallenneta'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          ),
        ]),
        const SizedBox(height: MSpace.xs),
        Text(
          tr(context, 'Viewers watch it as it happens; nothing is saved after it ends. Chat messages are kept for 30 days.',
              'Katsojat näkevät sen reaaliajassa, eikä mitään tallenneta lähetyksen jälkeen. Chat-viestit säilytetään 30 päivää.'),
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: MTextSize.bodyM),
        ),
        const SizedBox(height: MSpace.md),
        Text(tr(context, 'Rules for lives', 'Lähetysten säännöt'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        const SizedBox(height: MSpace.sm),
        point(Icons.checkroom_rounded, tr(context, 'Show the real products you sell, as they are.', 'Näytä myymäsi oikeat tuotteet sellaisina kuin ne ovat.')),
        point(Icons.sell_outlined, tr(context, 'Prices you say must match the prices in the app.', 'Kertomiesi hintojen on vastattava sovelluksen hintoja.')),
        point(Icons.percent_rounded, tr(context, 'A discount you announce must follow the 30-day rule: compare with the lowest price of the 30 days before it.',
            'Ilmoittamasi alennuksen on noudatettava 30 päivän sääntöä: vertaa alennusta edeltävän 30 päivän alimpaan hintaan.')),
        point(Icons.timer_off_outlined, tr(context, 'No false urgency: do not say stock or time is running out when it is not.',
            'Ei keksittyä kiirettä: älä väitä varaston tai ajan loppuvan, jos se ei pidä paikkaansa.')),
        point(Icons.handshake_outlined, tr(context, 'Say clearly when a live or a product is paid cooperation (advertising).',
            'Kerro selvästi, kun lähetys tai tuote on maksettua yhteistyötä (mainontaa).')),
        point(Icons.child_care_rounded, tr(context, 'No children or bystanders on camera without consent (a guardian\'s for children).',
            'Ei lapsia tai sivullisia kuvassa ilman suostumusta (lapsilta huoltajan suostumus).')),
        point(Icons.music_note_rounded, tr(context, 'Play only music you have a licence for, including for online streaming.',
            'Soita vain musiikkia, johon sinulla on lupa, myös verkkolähetyksiin.')),
        point(Icons.card_giftcard_rounded, tr(context, 'Giveaways follow the rules: state who may take part, how the winner is chosen and when it ends.',
            'Arvonnat noudattavat sääntöjä: kerro, kuka voi osallistua, miten voittaja valitaan ja milloin arvonta päättyy.')),
        point(Icons.flag_outlined, tr(context, 'Viewers can report a live, and Malvoya may end one that breaks the rules.',
            'Katsojat voivat ilmoittaa lähetyksestä, ja Malvoya voi lopettaa sääntöjä rikkovan lähetyksen.')),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: EdgeInsets.zero),
          onPressed: () => openLegal('sellers'),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(tr(context, 'Full rules in the Seller Terms', 'Kaikki säännöt myyjän ehdoissa')),
        ),
      ]),
    );
  }

  Widget _footer() {
    final hint = !_titleOk
        ? tr(context, 'Add a title (3–100 characters).', 'Lisää otsikko (3–100 merkkiä).')
        : _selected.isEmpty
            ? tr(context, 'Pick at least one product.', 'Valitse vähintään yksi tuote.')
            : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.md),
      decoration: const BoxDecoration(color: AppTheme.surface, border: Border(top: BorderSide(color: AppTheme.divider))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: MSpace.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, height: 1.35)),
            ),
          )
        else if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: MSpace.sm),
            child: Text(hint, style: const TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.caption)),
          ),
        MButton(
          label: tr(context, 'Start live', 'Aloita lähetys'),
          icon: Icons.sensors_rounded,
          expand: true,
          loading: _starting,
          onPressed: _canStart ? _start : null,
        ),
      ]),
    );
  }
}
