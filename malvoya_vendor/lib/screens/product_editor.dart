import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/api_client.dart';
import '../core/haptics.dart';
import '../core/images.dart';
import '../core/media_upload.dart';
import '../core/strings.dart';

/// Categories shared with the customer app's home screen and catalogue.
const productCategories = ['Clothing', 'Shoes', 'Bags', 'Accessories', 'Jewelry', 'Beauty', 'Home', 'Other'];
const productSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'One Size', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45'];
const productColors = ['Black', 'White', 'Grey', 'Beige', 'Brown', 'Blue', 'Green', 'Red', 'Pink', 'Purple', 'Yellow', 'Multi'];

/// Finnish names for the values above. The API keeps the English values (shared with the customer app).
const _categoryFi = {
  'Clothing': 'Vaatteet', 'Shoes': 'Kengät', 'Bags': 'Laukut', 'Accessories': 'Asusteet', 'Jewelry': 'Korut',
  'Beauty': 'Kauneus', 'Home': 'Koti', 'Other': 'Muu',
};
const _colorFi = {
  'Black': 'Musta', 'White': 'Valkoinen', 'Grey': 'Harmaa', 'Beige': 'Beige', 'Brown': 'Ruskea', 'Blue': 'Sininen',
  'Green': 'Vihreä', 'Red': 'Punainen', 'Pink': 'Vaaleanpunainen', 'Purple': 'Violetti', 'Yellow': 'Keltainen', 'Multi': 'Monivärinen',
};
const _sizeFi = {'One Size': 'Yksi koko'};

class _Option {
  int? id;
  String? size;
  String? color;
  int stock;
  _Option({this.id, this.size, this.color, this.stock = 1});
}

class _Photo {
  String? url;
  double progress = 0;
  String? error;
  _Photo({this.url});
}

/// A product video: already on the product ([id] set), or uploaded and waiting to be attached on save.
class _Video {
  int? id;
  String? poster;
  String status; // UPLOADING | PENDING (uploaded, attached on save) | PROCESSING | READY | FAILED
  UploadedMedia? upload;
  double progress = 0;
  String? error;
  _Video({this.id, this.poster, this.status = 'UPLOADING'});
}

/// Create or edit a product. Photos upload as soon as they are picked.
class ProductEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  const ProductEditorScreen({super.key, this.product});

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?['name'] ?? '');
  late final _description = TextEditingController(text: widget.product?['description'] ?? '');
  late final _price = TextEditingController(
      text: widget.product?['salePriceCents'] != null ? ((widget.product!['salePriceCents'] as num) / 100).toStringAsFixed(2).replaceAll('.', ',') : '');
  late final _stock = TextEditingController(text: '${widget.product?['stockQuantity'] ?? 1}');

  // Imported products may bring their own category, sizes and colours: keep them selectable
  late String _category = '${widget.product?['category'] ?? ''}'.trim().isEmpty ? 'Clothing' : '${widget.product!['category']}'.trim();
  late final List<String> _categories = [...productCategories, if (!productCategories.contains(_category)) _category];
  late String _condition = const ['NEW', 'LIKE_NEW', 'GOOD', 'FAIR', 'POOR'].contains(widget.product?['condition']) ? widget.product!['condition'] : 'NEW';
  late bool _secondHand = widget.product?['isSecondHand'] == true;
  late bool _eco = widget.product?['isEcoFriendly'] == true;
  late bool _handmade = widget.product?['isHandmade'] == true;
  late bool _available = widget.product?['isAvailable'] != false;
  late final List<_Photo> _photos = ((widget.product?['images'] as List?) ?? []).map((u) => _Photo(url: '$u')).toList();
  late final List<_Video> _videos = ((widget.product?['videos'] as List?) ?? [])
      .map((v) => _Video(id: v['id'], poster: v['poster'], status: '${v['status'] ?? 'READY'}'))
      .toList();
  static const _maxVideos = 3;
  late final List<_Option> _options = ((widget.product?['variants'] as List?) ?? [])
      .map((v) => _Option(id: asInt(v['id']), size: v['size'], color: v['color'], stock: asInt(v['stock']) ?? 0))
      .toList();

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  /// What the form looked like when opened, to ask before throwing changes away.
  late final String _initial;

  @override
  void initState() {
    super.initState();
    _initial = _snapshot();
  }

  String _snapshot() => jsonEncode({
        'name': _name.text, 'description': _description.text, 'price': _price.text, 'stock': _stock.text,
        'category': _category, 'condition': _condition, 'secondHand': _secondHand, 'eco': _eco, 'handmade': _handmade,
        'available': _available,
        'photos': _photos.map((p) => p.url ?? 'uploading').toList(),
        'videos': _videos.map((v) => v.id ?? v.status).toList(),
        'options': _options.map((o) => [o.id, o.size, o.color, o.stock]).toList(),
      });

  bool get _hasChanges => !_saving && !_deleting && _snapshot() != _initial;

  String _show(Map<String, String> fi, String value) => isFinnish(context) ? (fi[value] ?? value) : value;

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Discard changes?', 'Hylätäänkö muutokset?')),
        content: Text(tr(ctx, 'Your changes to this product have not been saved.', 'Tuotteeseen tekemiäsi muutoksia ei ole tallennettu.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Keep editing', 'Jatka muokkausta'))),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD93025), side: const BorderSide(color: Color(0xFFD93025), width: 1.5), minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Discard', 'Hylkää')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  /// DELETE /products/:id. From API 2.10 the answer says what happened: `deleted: "hard"` (never ordered,
  /// erased) or `"soft"` (kept only for past orders' records, gone from every list). Older servers only
  /// hide it, and it stays in the store's own list.
  Future<void> _delete() async {
    const red = Color(0xFFD93025);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Remove this product?', 'Poistetaanko tuote?')),
        content: Text(tr(ctx,
            'Shoppers will no longer see or buy it. To only take it off sale for a while, switch it to sold out instead.',
            'Asiakkaat eivät enää näe tai voi ostaa sitä. Jos haluat poistaa sen myynnistä vain väliaikaisesti, merkitse se loppuneeksi.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Back', 'Takaisin'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white, minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Remove', 'Poista')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final res = await _api.delete('/products/${widget.product!['id']}');
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _deleting = false;
        _error = res.errorMessage;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    final name = '${widget.product!['name'] ?? ''}'.trim();
    final message = switch ('${res.data['deleted'] ?? ''}') {
      'hard' => tr(context, 'Product deleted.', 'Tuote poistettu.'),
      'soft' => tr(context, 'Product removed. It is kept only in the records of past orders.', 'Tuote poistettu. Se säilyy vain aiempien tilausten tiedoissa.'),
      _ => tr(context, 'Product hidden from shoppers. Past orders refer to it, so it stays in your list as hidden.',
          'Tuote piilotettu asiakkailta. Aiemmat tilaukset viittaavat siihen, joten se jää listaasi piilotettuna.'),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(name.isEmpty ? message : '$name: $message')));
    Navigator.pop(context, true);
  }

  bool get _editing => widget.product != null;
  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  static const _tipsSeenKey = 'photo_tips_seen';

  /// Three short tips for photos that sell; shown before the first photo on this phone, and any
  /// time from "Photo tips".
  Future<void> _showPhotoTips() {
    Haptics.select();
    Widget tip(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppTheme.sunshineLight, shape: BoxShape.circle),
              child: Icon(icon, color: const Color(0xFF8A5A00), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(body, style: const TextStyle(color: AppTheme.textSecondary, height: 1.35)),
              ]),
            ),
          ]),
        );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(ctx, 'Photos that sell', 'Myyvät kuvat'), style: AppTheme.display(size: 21)),
            const SizedBox(height: 14),
            tip(Icons.wb_sunny_outlined, tr(ctx, 'Good light', 'Hyvä valo'),
                tr(ctx, 'Daylight from a window, no flash. Colours then look true.', 'Päivänvaloa ikkunasta, ei salamaa. Silloin värit näkyvät oikein.')),
            tip(Icons.crop_portrait_rounded, tr(ctx, 'Plain background', 'Yksinkertainen tausta'),
                tr(ctx, 'A wall or a sheet in one colour keeps the eye on the item.', 'Yksivärinen seinä tai lakana pitää katseen tuotteessa.')),
            tip(Icons.threesixty_rounded, tr(ctx, 'At least 3 angles', 'Vähintään 3 kuvakulmaa'),
                tr(ctx, 'Front, back and a close-up of the fabric or label. The first photo is the cover; drag photos to change the order.',
                    'Edestä, takaa ja lähikuva kankaasta tai merkistä. Ensimmäinen kuva on kansikuva; vedä kuvia muuttaaksesi järjestystä.')),
            const SizedBox(height: 4),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'Got it', 'Selvä'))),
          ]),
        ),
      ),
    );
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 8) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_tipsSeenKey) != true) {
        await prefs.setBool(_tipsSeenKey, true);
        if (!mounted) return;
        await _showPhotoTips();
        if (!mounted) return;
      }
    } catch (_) {}
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr(context, 'Take a photo', 'Ota kuva')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr(context, 'Choose from gallery', 'Valitse galleriasta')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (picked == null || !mounted) return;
    final photo = _Photo();
    setState(() => _photos.add(photo));
    try {
      final url = await MediaUpload.uploadImage(
        api: _api,
        kind: 'product_image',
        file: File(picked.path),
        onProgress: (p) {
          if (mounted) setState(() => photo.progress = p);
        },
      );
      if (mounted) setState(() => photo.url = url);
    } catch (e) {
      if (mounted) setState(() => photo.error = '$e');
    }
  }

  Future<void> _addVideo() async {
    if (_videos.length >= _maxVideos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.videocam_outlined), title: Text(tr(context, 'Record a video', 'Kuvaa video')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.video_library_outlined), title: Text(tr(context, 'Choose from gallery', 'Valitse galleriasta')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    if (picked == null || !mounted) return;
    final video = _Video();
    setState(() => _videos.add(video));
    try {
      final media = await MediaUpload.upload(
        api: _api,
        kind: 'product_video',
        file: File(picked.path),
        onProgress: (p) {
          if (mounted) setState(() => video.progress = p);
        },
      );
      if ((media.durationSec ?? 0) > 60) throw UploadException(tr(context, 'Product videos can be up to 60 seconds.', 'Tuotevideo voi olla enintään 60 sekuntia.'));
      video.upload = media;
      if (_editing) {
        await _attach(widget.product!['id'], video);
      } else if (mounted) {
        setState(() => video.status = 'PENDING');
      }
    } catch (e) {
      if (mounted) setState(() => video.error = '$e');
    }
  }

  /// Adds an uploaded video to the product; the server checks the upload belongs to this store.
  Future<String?> _attach(Object productId, _Video video) async {
    final res = await _api.post('/products/$productId/videos', video.upload!.toProof());
    if (!mounted) return null;
    setState(() {
      if (res.ok) {
        video.id = res.data['video']['id'];
        video.poster = res.data['video']['poster'];
        video.status = '${res.data['video']['status']}';
      } else {
        video.error = res.error;
      }
    });
    return res.ok ? null : res.error;
  }

  Future<void> _removeVideo(_Video video) async {
    if (video.id != null && _editing) {
      final res = await _api.delete('/products/${widget.product!['id']}/videos/${video.id}');
      if (!res.ok) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.errorMessage)));
        return;
      }
    }
    if (mounted) setState(() => _videos.remove(video));
  }

  int? _priceCents() {
    final v = double.tryParse(_price.text.trim().replaceAll(',', '.').replaceAll('€', ''));
    return v == null || v <= 0 ? null : (v * 100).round();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_photos.any((p) => p.url == null && p.error == null)) {
      setState(() => _error = tr(context, 'Wait for the photos to finish uploading.', 'Odota, että kuvat on ladattu.'));
      return;
    }
    if (_videos.any((v) => v.status == 'UPLOADING' && v.error == null)) {
      setState(() => _error = tr(context, 'Wait for the videos to finish uploading.', 'Odota, että videot on ladattu.'));
      return;
    }
    if (_options.any((o) => (o.size == null && o.color == null))) {
      setState(() => _error = tr(context, 'Each option needs a size or a colour.', 'Jokaisella vaihtoehdolla on oltava koko tai väri.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category,
      'condition': _condition,
      'isSecondHand': _secondHand,
      'isEcoFriendly': _eco,
      'isHandmade': _handmade,
      'salePriceCents': _priceCents(),
      'canBeSold': true,
      'images': _photos.where((p) => p.url != null).map((p) => p.url).toList(),
      if (_options.isEmpty) 'stockQuantity': int.tryParse(_stock.text.trim()) ?? 0,
      'variants': _options
          .map((o) => {
                if (o.id != null) 'id': o.id,
                if (o.size != null) 'size': o.size,
                if (o.color != null) 'color': o.color,
                'stock': o.stock,
              })
          .toList(),
      if (_editing) 'isAvailable': _available,
    };
    final api = _api;
    // A visible product needs the Seller Terms in force: on 428 the agreement sheet opens and the save is
    // sent again once they are accepted (the 428 comes before anything is saved)
    final res = await withAgreement(
      context,
      api,
      () => _editing ? api.patch('/products/${widget.product!['id']}', body) : api.post('/products', body),
    );
    if (!mounted) return;
    if (res.ok) {
      // Videos picked while creating the product are attached once it exists
      final productId = _editing ? widget.product!['id'] : res.data['product']?['id'];
      final pending = _videos.where((v) => v.status == 'PENDING' && v.error == null).toList();
      String? videoError;
      for (final v in pending) {
        videoError = await _attach(productId, v) ?? videoError;
      }
      if (!mounted) return;
      if (videoError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr(context, 'The product was saved, but a video could not be added', 'Tuote tallennettiin, mutta videota ei voitu lisätä')}: $videoError'),
        ));
      }
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = res.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(_editing ? tr(context, 'Edit product', 'Muokkaa tuotetta') : tr(context, 'New product', 'Uusi tuote'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Row(children: [
              Expanded(child: _label(tr(context, 'Photos', 'Kuvat'))),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _showPhotoTips,
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                label: Text(tr(context, 'Photo tips', 'Kuvavinkit')),
              ),
            ]),
            SizedBox(
              height: 112,
              // The images list is saved in this order (the first is the cover): long-press and drag to move
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: _photos.length,
                onReorderStart: (_) => Haptics.select(),
                onReorder: (from, to) => setState(() {
                  if (to > from) to--;
                  _photos.insert(to, _photos.removeAt(from));
                }),
                proxyDecorator: (child, _, __) => Material(color: Colors.transparent, elevation: 6, borderRadius: BorderRadius.circular(14), child: child),
                itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
                  key: ObjectKey(_photos[i]),
                  index: i,
                  child: _photoTile(_photos[i], cover: i == 0),
                ),
                footer: _photos.length < 8
                    ? Semantics(
                        button: true,
                        label: tr(context, 'Add photo', 'Lisää kuva'),
                        child: GestureDetector(
                          onTap: _addPhoto,
                          child: Container(
                            width: 90,
                            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.add_a_photo_outlined, color: AppTheme.primary, size: 30),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
                tr(context,
                    'Good light, a plain background and at least 3 angles show the item clearly. The first photo is the cover — long-press a photo and drag it to change the order. Use your own photos, or ones the brand allows you to use.',
                    'Hyvä valo, yksinkertainen tausta ja vähintään 3 kuvakulmaa näyttävät tuotteen selkeästi. Ensimmäinen kuva on kansikuva — paina kuvaa pitkään ja vedä muuttaaksesi järjestystä. Käytä omia kuviasi tai kuvia, joiden käyttöön brändi on antanut luvan.'),
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            if (_photos.isNotEmpty && _photos.length < 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    tr(context, 'Add ${3 - _photos.length} more angle${_photos.length == 2 ? '' : 's'} so shoppers can see the whole item.',
                        'Lisää vielä ${3 - _photos.length} kuvakulma${_photos.length == 2 ? '' : 'a'}, jotta asiakkaat näkevät koko tuotteen.'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00), fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 20),
            _label(tr(context, 'Videos', 'Videot')),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final v in _videos) _videoTile(v),
                  if (_videos.length < _maxVideos)
                    GestureDetector(
                      onTap: _addVideo,
                      child: Container(
                        width: 90,
                        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.video_call_outlined, color: AppTheme.primary, size: 32),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
                tr(context, 'Up to 3 videos of 60 seconds, with sound. Show the fit, the fabric moving and the details. Use only music you have the rights to.',
                    'Enintään 3 videota, 60 sekuntia, äänen kanssa. Näytä istuvuus, kankaan liike ja yksityiskohdat. Käytä vain musiikkia, johon sinulla on oikeudet.'),
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              maxLength: 200,
              decoration: InputDecoration(labelText: tr(context, 'Name', 'Nimi')),
              validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'Give the product a name', 'Anna tuotteelle nimi') : null,
            ),
            TextFormField(
              controller: _description,
              maxLength: 2000,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr(context, 'Description, materials and fit', 'Kuvaus, materiaalit ja istuvuus')),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr(context, 'Price (€, VAT included)', 'Hinta (€, sis. ALV)'), prefixIcon: const Icon(Icons.euro_rounded)),
              validator: (_) => _priceCents() == null ? tr(context, 'Enter a price', 'Anna hinta') : null,
            ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr(context, 'When you lower a price, shoppers see a reduction only if the old price was the lowest of the previous 30 days (EU rule).',
                      'Kun lasket hintaa, alennus näytetään vain, jos vanha hinta oli edeltävän 30 päivän alin (EU-sääntö).'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(labelText: tr(context, 'Category', 'Kategoria')),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(_show(_categoryFi, c)))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _condition,
              decoration: InputDecoration(labelText: tr(context, 'Condition', 'Kunto')),
              items: {
                'NEW': tr(context, 'New', 'Uusi'),
                'LIKE_NEW': tr(context, 'Like new', 'Kuin uusi'),
                'GOOD': tr(context, 'Good', 'Hyvä'),
                'FAIR': tr(context, 'Fair', 'Kohtalainen'),
                'POOR': tr(context, 'Worn', 'Kulunut'),
              }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _condition = v!),
            ),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _secondHand, onChanged: (v) => setState(() => _secondHand = v), title: Text(tr(context, 'Second hand', 'Käytetty'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _eco, onChanged: (v) => setState(() => _eco = v), title: Text(tr(context, 'Eco-friendly', 'Ympäristöystävällinen'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _handmade, onChanged: (v) => setState(() => _handmade = v), title: Text(tr(context, 'Handmade', 'Käsintehty'))),
            const Divider(height: 32),
            Row(children: [
              Expanded(child: _label(tr(context, 'Sizes and colours', 'Koot ja värit'))),
              TextButton.icon(
                onPressed: () => setState(() => _options.add(_Option())),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr(context, 'Add option', 'Lisää vaihtoehto')),
              ),
            ]),
            if (_options.isEmpty) ...[
              Text(tr(context, 'No options: the item is sold as one piece.', 'Ei vaihtoehtoja: tuotetta myydään yhtenä.'),
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _stock,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr(context, 'How many do you have?', 'Montako kappaletta sinulla on?')),
                validator: (v) => int.tryParse((v ?? '').trim()) == null ? tr(context, 'Enter a number', 'Anna luku') : null,
              ),
            ],
            for (final o in _options) _optionRow(o),
            if (_editing) ...[
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _available,
                onChanged: (v) => setState(() => _available = v),
                title: Text(tr(context, 'Visible in the store', 'Näkyy kaupassa')),
                subtitle: Text(widget.product?['importJobId'] != null && widget.product?['isAvailable'] == false
                    ? tr(context, 'Imported products stay hidden until you switch this on. Check the photos, price and stock first.',
                        'Tuodut tuotteet pysyvät piilossa, kunnes kytket tämän päälle. Tarkista ensin kuvat, hinta ja varastosaldo.')
                    : tr(context, 'Turn off to hide it without deleting.', 'Piilota poistamatta.')),
              ),
            ],
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving || _deleting ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_editing ? tr(context, 'Save changes', 'Tallenna muutokset') : tr(context, 'Add product', 'Lisää tuote')),
              ),
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD93025), side: const BorderSide(color: Color(0xFFD93025), width: 1.5)),
                onPressed: _saving || _deleting ? null : _delete,
                icon: _deleting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_outline_rounded),
                label: Text(tr(context, 'Remove product', 'Poista tuote')),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
      );

  Widget _photoTile(_Photo p, {bool cover = false}) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 90,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: AppTheme.primaryLight),
                if (p.url != null) NetImage(p.url!, width: 90, height: 112),
                if (p.url == null && p.error == null)
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(value: p.progress > 0 ? p.progress : null, color: AppTheme.primary),
                      if (p.progress > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${(p.progress * 100).round()} %', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                        ),
                    ]),
                  ),
                if (cover && p.url != null)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(8)),
                      child: Text(tr(context, 'Cover', 'Kansi'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                    ),
                  ),
                if (p.error != null)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Center(child: Text(p.error!, style: const TextStyle(fontSize: 10, color: AppTheme.accent), textAlign: TextAlign.center)),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label: tr(context, 'Remove photo', 'Poista kuva'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _photos.remove(p));
                      },
                      // 48 px touch area around the small visible button
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(2),
                            child: CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 14, color: Colors.white)),
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
      );

  Widget _videoTile(_Video v) {
    final label = v.error != null
        ? v.error!
        : switch (v.status) {
            'UPLOADING' => '${(v.progress * 100).round()} %',
            'PENDING' => tr(context, 'Added on save', 'Lisätään tallennettaessa'),
            'PROCESSING' => tr(context, 'Processing…', 'Käsitellään…'),
            'FAILED' => tr(context, 'Could not process', 'Käsittely epäonnistui'),
            _ => null,
          };
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 90,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black87),
              if (v.poster != null) CachedNetworkImage(imageUrl: v.poster!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
              if (v.status == 'UPLOADING' && v.error == null)
                Center(child: CircularProgressIndicator(value: v.progress > 0 ? v.progress : null, color: Colors.white)),
              if (v.status == 'READY') const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34)),
              if (label != null)
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 6,
                  child: Text(label, textAlign: TextAlign.center, maxLines: 3, style: TextStyle(fontSize: 10, color: v.error != null ? AppTheme.accent : Colors.white, fontWeight: FontWeight.w600)),
                ),
              Positioned(
                top: 2,
                right: 2,
                child: Semantics(
                  button: true,
                  label: tr(context, 'Remove video', 'Poista video'),
                  child: GestureDetector(
                    onTap: () => _removeVideo(v),
                    child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 14, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionRow(_Option o) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.divider)),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: o.size,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr(context, 'Size', 'Koko')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr(context, 'None', 'Ei'))),
                  ...{...productSizes, if (o.size != null) o.size!}.map((s) => DropdownMenuItem(value: s, child: Text(_show(_sizeFi, s)))),
                ],
                onChanged: (v) => setState(() => o.size = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: o.color,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr(context, 'Colour', 'Väri')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr(context, 'None', 'Ei'))),
                  ...{...productColors, if (o.color != null) o.color!}.map((c) => DropdownMenuItem(value: c, child: Text(_show(_colorFi, c), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => o.color = v),
              ),
            ),
            const SizedBox(width: 6),
          ]),
          Row(children: [
            Text(tr(context, 'In stock', 'Varastossa'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              tooltip: tr(context, 'One less', 'Yksi vähemmän'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: o.stock > 0 ? () => setState(() => o.stock--) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(width: 36, child: Text('${o.stock}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(
              tooltip: tr(context, 'One more', 'Yksi lisää'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => setState(() => o.stock++),
              icon: const Icon(Icons.add_circle_outline),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: tr(context, 'Remove option', 'Poista vaihtoehto'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.accent),
              onPressed: () => setState(() => _options.remove(o)),
            ),
          ]),
        ]),
      );
}
