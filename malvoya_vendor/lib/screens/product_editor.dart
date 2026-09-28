import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/media_upload.dart';
import '../core/strings.dart';

/// Categories shared with the customer app's home screen and catalogue.
const productCategories = ['Clothing', 'Shoes', 'Bags', 'Accessories', 'Jewelry', 'Beauty', 'Home', 'Other'];
const productSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'One Size', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45'];
const productColors = ['Black', 'White', 'Grey', 'Beige', 'Brown', 'Blue', 'Green', 'Red', 'Pink', 'Purple', 'Yellow', 'Multi'];

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

  late String _category = productCategories.contains(widget.product?['category']) ? widget.product!['category'] : 'Clothing';
  late String _condition = widget.product?['condition'] ?? 'NEW';
  late bool _secondHand = widget.product?['isSecondHand'] == true;
  late bool _eco = widget.product?['isEcoFriendly'] == true;
  late bool _handmade = widget.product?['isHandmade'] == true;
  late bool _available = widget.product?['isAvailable'] != false;
  late final List<_Photo> _photos = ((widget.product?['images'] as List?) ?? []).map((u) => _Photo(url: '$u')).toList();
  late final List<_Option> _options = ((widget.product?['variants'] as List?) ?? [])
      .map((v) => _Option(id: asInt(v['id']), size: v['size'], color: v['color'], stock: asInt(v['stock']) ?? 0))
      .toList();

  bool _saving = false;
  String? _error;

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

  Future<void> _addPhoto() async {
    if (_photos.length >= 8) return;
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
    final res = _editing ? await _api.patch('/products/${widget.product!['id']}', body) : await _api.post('/products', body);
    if (!mounted) return;
    if (res.ok) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = res.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(_editing ? tr(context, 'Edit product', 'Muokkaa tuotetta') : tr(context, 'New product', 'Uusi tuote'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            _label(tr(context, 'Photos', 'Kuvat')),
            SizedBox(
              height: 112,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in _photos) _photoTile(p),
                  if (_photos.length < 8)
                    GestureDetector(
                      onTap: _addPhoto,
                      child: Container(
                        width: 90,
                        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.add_a_photo_outlined, color: AppTheme.primary, size: 30),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(tr(context, 'Good light and a plain background sell best. The first photo is the cover.', 'Hyvä valo ja yksinkertainen tausta myyvät parhaiten. Ensimmäinen kuva on kansikuva.'),
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
              items: productCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
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
                subtitle: Text(tr(context, 'Turn off to hide it without deleting.', 'Piilota poistamatta.')),
              ),
            ],
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_editing ? tr(context, 'Save changes', 'Tallenna muutokset') : tr(context, 'Add product', 'Lisää tuote')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
      );

  Widget _photoTile(_Photo p) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 90,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: AppTheme.primaryLight),
                if (p.url != null) CachedNetworkImage(imageUrl: p.url!, fit: BoxFit.cover),
                if (p.url == null && p.error == null)
                  Center(child: CircularProgressIndicator(value: p.progress > 0 ? p.progress : null, color: AppTheme.primary)),
                if (p.error != null)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Center(child: Text(p.error!, style: const TextStyle(fontSize: 10, color: AppTheme.accent), textAlign: TextAlign.center)),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _photos.remove(p)),
                    child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 14, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _optionRow(_Option o) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.divider)),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: o.size,
                isDense: true,
                decoration: InputDecoration(labelText: tr(context, 'Size', 'Koko'), isDense: true),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr(context, 'None', 'Ei'))),
                  ...productSizes.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (v) => setState(() => o.size = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: o.color,
                isDense: true,
                decoration: InputDecoration(labelText: tr(context, 'Colour', 'Väri'), isDense: true),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr(context, 'None', 'Ei'))),
                  ...productColors.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => setState(() => o.color = v),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                Text(tr(context, 'In stock', 'Varastossa'), style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
                Row(children: [
                  InkWell(onTap: o.stock > 0 ? () => setState(() => o.stock--) : null, child: const Icon(Icons.remove_circle_outline, size: 22)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('${o.stock}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  InkWell(onTap: () => setState(() => o.stock++), child: const Icon(Icons.add_circle_outline, size: 22)),
                ]),
              ],
            ),
            IconButton(
              tooltip: tr(context, 'Remove', 'Poista'),
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.accent),
              onPressed: () => setState(() => _options.remove(o)),
            ),
          ],
        ),
      );
}
