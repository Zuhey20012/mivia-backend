part of '../product_editor.dart';

/// Photos (the minimum set per category, spec §4), videos and label / safety photos.
extension _EditorPhotos on _ProductEditorScreenState {
  static const _tipsSeenKey = 'photo_tips_seen';

  /// What to photograph for this kind of product.
  String _minimumPhotos() {
    if (_secondHand && _topSlug == 'clothing') {
      return tr(context, 'Front, back, the size and material label (or say it is missing) and each defect.',
          'Edestä, takaa, koko- ja materiaalilappu (tai kerro, että se puuttuu) ja jokainen vika.');
    }
    return switch (_topSlug) {
      'clothing' || 'sport' => tr(context, 'Front, back and a close-up of the fabric or print.', 'Edestä, takaa ja lähikuva kankaasta tai kuosista.'),
      'shoes' => tr(context, 'Side view, the pair from the front, and the sole.', 'Sivukuva, pari edestä ja pohja.'),
      'bags' => tr(context, 'Front, back and inside.', 'Edestä, takaa ja sisältä.'),
      'accessories' => tr(context, 'Front and a detail.', 'Edestä ja yksityiskohta.'),
      'jewellery' => tr(context, 'On a plain background, and a close-up of the clasp or stamp.', 'Yksivärisellä taustalla sekä lähikuva lukosta tai leimasta.'),
      'makeup' => tr(context, 'The pack, and a swatch of each shade (on skin or paper).', 'Pakkaus ja näyte jokaisesta sävystä (iholla tai paperilla).'),
      'skincare' || 'haircare' => tr(context, 'The front of the pack and the back or ingredient panel.', 'Pakkauksen etupuoli ja takapuoli tai ainesosaluettelo.'),
      'fragrance' => tr(context, 'The bottle and the front of the box.', 'Pullo ja pakkauksen etupuoli.'),
      _ => tr(context, 'Good light, a plain background and at least 3 angles.', 'Hyvä valo, yksinkertainen tausta ja vähintään 3 kuvakulmaa.'),
    };
  }

  Future<void> _showPhotoTips() {
    Haptics.selection();
    final c = context.mColors;
    Widget tip(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: MSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 20, backgroundColor: c.sunshineSoft, child: Icon(icon, color: c.onSunshineSoft, size: 22)),
            const SizedBox(width: MSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: MType.bodyL.copyWith(fontWeight: FontWeight.w800)),
                Text(body, style: MType.bodyM.copyWith(color: c.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
    return showMSheet<void>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Photos that sell', 'Myyvät kuvat'),
          actions: [MButton(label: tr(ctx, 'Got it', 'Selvä'), expand: true, onPressed: () => Navigator.pop(ctx))],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            tip(Icons.wb_sunny_outlined, tr(ctx, 'Good light', 'Hyvä valo'),
                tr(ctx, 'Daylight from a window, no flash and no filters. Colours then look true.', 'Päivänvaloa ikkunasta, ei salamaa eikä suodattimia. Silloin värit näkyvät oikein.')),
            tip(Icons.crop_portrait_rounded, tr(ctx, 'Plain background', 'Yksinkertainen tausta'),
                tr(ctx, 'A wall or a sheet in one colour keeps the eye on the item.', 'Yksivärinen seinä tai lakana pitää katseen tuotteessa.')),
            tip(Icons.threesixty_rounded, tr(ctx, 'For this category', 'Tässä kategoriassa'), _minimumPhotos()),
          ]),
        ));
  }

  Future<ImageSource?> _askSource({bool video = false}) => showMSheet<ImageSource>(context, builder: (ctx) => MSheet(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MListTile(
            icon: video ? Icons.videocam_outlined : Icons.photo_camera_outlined,
            title: video ? tr(ctx, 'Record a video', 'Kuvaa video') : tr(ctx, 'Take a photo', 'Ota kuva'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          MListTile(
            icon: video ? Icons.video_library_outlined : Icons.photo_library_outlined,
            title: tr(ctx, 'Choose from gallery', 'Valitse galleriasta'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ));

  Future<void> _addPhoto({bool safety = false}) async {
    final list = safety ? _safetyPhotos : _photos;
    if (list.length >= (safety ? 6 : _ProductEditorScreenState._maxPhotos)) return;
    if (!safety) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_tipsSeenKey) != true) {
          await prefs.setBool(_tipsSeenKey, true);
          if (!mounted) return;
          await _showPhotoTips();
          if (!mounted) return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final source = await _askSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (picked == null || !mounted) return;
    final photo = _Photo();
    _update(() => list.add(photo));
    _touch('images');
    final api = _api;
    try {
      final url = await MediaUpload.uploadImage(
        api: api,
        kind: 'product_image',
        file: File(picked.path),
        onProgress: (p) {
          if (mounted) _update(() => photo.progress = p);
        },
      );
      if (mounted) _update(() => photo.url = url);
    } catch (e) {
      if (mounted) _update(() => photo.error = ServerMessages.localize('$e'));
    }
  }

  Future<void> _addVideo() async {
    if (_videos.length >= _ProductEditorScreenState._maxVideos) return;
    final source = await _askSource(video: true);
    if (source == null) return;
    final picked = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    if (picked == null || !mounted) return;
    final video = _Video();
    _update(() => _videos.add(video));
    final tooLong = tr(context, 'Product videos can be up to 60 seconds.', 'Tuotevideo voi olla enintään 60 sekuntia.');
    try {
      final media = await MediaUpload.upload(
        api: _api,
        kind: 'product_video',
        file: File(picked.path),
        onProgress: (p) {
          if (mounted) _update(() => video.progress = p);
        },
      );
      if ((media.durationSec ?? 0) > 60) throw UploadException(tooLong);
      video.upload = media;
      if (_editing) {
        await _attach(_p!['id'], video);
      } else if (mounted) {
        _update(() => video.status = 'PENDING');
      }
    } catch (e) {
      if (mounted) _update(() => video.error = '$e');
    }
  }

  /// Adds an uploaded video to the product; the server checks the upload belongs to this store.
  Future<String?> _attach(Object? productId, _Video video) async {
    final res = await _api.post('/products/$productId/videos', video.upload!.toProof());
    if (!mounted) return null;
    _update(() {
      if (res.ok) {
        video.id = asInt(res.data['video']['id']);
        video.poster = res.data['video']['poster'] as String?;
        video.status = '${res.data['video']['status']}';
      } else {
        video.error = res.error;
      }
    });
    return res.ok ? null : res.error;
  }

  Future<void> _removeVideo(_Video video) async {
    if (video.id != null && _editing) {
      final res = await _api.delete('/products/${_p!['id']}/videos/${video.id}');
      if (!res.ok) {
        if (mounted) MSnack.error(context, res.errorMessage);
        return;
      }
    }
    if (mounted) _update(() => _videos.remove(video));
  }

  Widget _addTile(IconData icon, String label, VoidCallback onTap) {
    final c = context.mColors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: MRadius.brSm,
        child: Container(
          width: 90,
          decoration: BoxDecoration(color: c.primarySoft, borderRadius: MRadius.brSm),
          child: Icon(icon, color: c.onPrimarySoft, size: 30),
        ),
      ),
    );
  }

  Widget _photoStrip(List<_Photo> list, {required bool safety}) {
    final max = safety ? 6 : _ProductEditorScreenState._maxPhotos;
    return SizedBox(
      height: 112,
      // Saved in this order (the first is the cover): long-press and drag to move
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: list.length,
        onReorderStart: (_) => Haptics.selection(),
        onReorder: (from, to) => _update(() {
          if (to > from) to--;
          list.insert(to, list.removeAt(from));
        }),
        proxyDecorator: (child, _, __) => Material(color: Colors.transparent, elevation: 6, borderRadius: MRadius.brSm, child: child),
        itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
          key: ObjectKey(list[i]),
          index: i,
          child: _photoTile(list, list[i], cover: i == 0 && !safety),
        ),
        footer: list.length < max
            ? _addTile(Icons.add_a_photo_outlined, safety ? tr(context, 'Add label photo', 'Lisää merkintäkuva') : tr(context, 'Add photo', 'Lisää kuva'), () => _addPhoto(safety: safety))
            : null,
      ),
    );
  }

  Widget _photoTile(List<_Photo> list, _Photo p, {bool cover = false}) {
    final c = context.mColors;
    return Padding(
      padding: const EdgeInsets.only(right: MSpace.sm),
      child: ClipRRect(
        borderRadius: MRadius.brSm,
        child: SizedBox(
          width: 90,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: c.primarySoft),
            if (p.url != null) NetImage(p.url!, width: 90, height: 112),
            if (p.url == null && p.error == null)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(value: p.progress > 0 ? p.progress : null, color: c.primary),
                  if (p.progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: MSpace.xs),
                      child: Text('${(p.progress * 100).round()} %', style: MType.caption.copyWith(fontWeight: FontWeight.w800, color: c.onPrimarySoft)),
                    ),
                ]),
              ),
            if (cover && p.url != null)
              Positioned(left: MSpace.xs, bottom: MSpace.xs, child: MBadge(tr(context, 'Cover', 'Kansi'), tone: MBadgeTone.sunshine, strong: true)),
            if (p.error != null)
              Padding(
                padding: const EdgeInsets.all(MSpace.xs),
                child: Center(child: Text(p.error!, style: MType.caption.copyWith(color: c.danger), textAlign: TextAlign.center)),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: tr(context, 'Remove photo', 'Poista kuva'),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _update(() => list.remove(p));
                  },
                  child: SizedBox(
                    width: kMinTouchTarget,
                    height: kMinTouchTarget,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircleAvatar(radius: 12, backgroundColor: MPalette.scrim, child: Icon(Icons.close_rounded, size: 14, color: MPalette.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _videoTile(_Video v) {
    final c = context.mColors;
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
      padding: const EdgeInsets.only(right: MSpace.sm),
      child: ClipRRect(
        borderRadius: MRadius.brSm,
        child: SizedBox(
          width: 90,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: c.inverseSurface),
            if (v.poster != null) CachedNetworkImage(imageUrl: v.poster!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
            if (v.status == 'UPLOADING' && v.error == null)
              Center(child: CircularProgressIndicator(value: v.progress > 0 ? v.progress : null, color: c.onInverseSurface)),
            if (v.status == 'READY') Center(child: Icon(Icons.play_circle_fill_rounded, color: MPalette.white, size: 34)),
            if (label != null)
              Positioned(
                left: MSpace.xs,
                right: MSpace.xs,
                bottom: MSpace.sm,
                child: Text(label, textAlign: TextAlign.center, maxLines: 3, style: MType.caption.copyWith(color: v.error != null ? c.danger : c.onInverseSurface, fontWeight: FontWeight.w600)),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: tr(context, 'Remove video', 'Poista video'),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _removeVideo(v),
                  child: SizedBox(
                    width: kMinTouchTarget,
                    height: kMinTouchTarget,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircleAvatar(radius: 12, backgroundColor: MPalette.scrim, child: Icon(Icons.close_rounded, size: 14, color: MPalette.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _photosSection() {
    final c = context.mColors;
    final ready = _photos.where((p) => p.url != null).length;
    return _section(tr(context, 'Photos', 'Kuvat'), Icons.photo_library_outlined, [
      _anchor(
        'images',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(_minimumPhotos(), style: MType.bodyM)),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget)),
              onPressed: _showPhotoTips,
              icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
              label: Text(tr(context, 'Tips', 'Vinkit')),
            ),
          ]),
          const SizedBox(height: MSpace.sm),
          _photoStrip(_photos, safety: false),
          const SizedBox(height: MSpace.xs),
          Text(
            tr(context, 'The first photo is the cover: long-press a photo and drag it to change the order. Use your own photos, or ones the brand allows you to use.',
                'Ensimmäinen kuva on kansikuva: paina kuvaa pitkään ja vedä muuttaaksesi järjestystä. Käytä omia kuviasi tai kuvia, joiden käyttöön brändi on antanut luvan.'),
            style: MType.caption.copyWith(color: c.onSurfaceVariant),
          ),
          if (ready > 0 && ready < 3)
            _issueLine(tr(context, 'Add ${3 - ready} more so shoppers see the whole item.', 'Lisää vielä ${3 - ready}, jotta asiakkaat näkevät koko tuotteen.'), danger: false),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr(context, 'Videos', 'Videot'), style: MType.label),
        const SizedBox(height: MSpace.xs),
        SizedBox(
          height: 150,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final v in _videos) _videoTile(v),
            if (_videos.length < _ProductEditorScreenState._maxVideos) _addTile(Icons.video_call_outlined, tr(context, 'Add video', 'Lisää video'), _addVideo),
          ]),
        ),
        const SizedBox(height: MSpace.xs),
        Text(
          tr(context, 'Up to 3 videos of 60 seconds. Use only music you have the rights to.', 'Enintään 3 videota, 60 sekuntia. Käytä vain musiikkia, johon sinulla on oikeudet.'),
          style: MType.caption.copyWith(color: c.onSurfaceVariant),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr(context, 'Label and safety photos', 'Merkintä- ja turvallisuuskuvat'), style: MType.label),
        Text(
          tr(context, 'Optional: the care label, warning panel or ingredient list. They add to the typed information, never replace it.',
              'Valinnainen: hoito-ohjelappu, varoitukset tai ainesosaluettelo. Ne täydentävät kirjoitettuja tietoja, eivät korvaa niitä.'),
          style: MType.caption.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: MSpace.xs),
        _photoStrip(_safetyPhotos, safety: true),
      ]),
    ]);
  }
}
