import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/media_upload.dart';

/// Record or pick a short video, or up to 10 photos with an optional sound track, link it to one of your products
/// and post it. A video plays with its own sound; photos play as a slideshow with the sound the store adds.
class CreateDropScreen extends StatefulWidget {
  const CreateDropScreen({super.key});

  @override
  State<CreateDropScreen> createState() => _CreateDropScreenState();
}

class _CreateDropScreenState extends State<CreateDropScreen> {
  /// The video (video drops)
  File? _file;
  bool _isVideo = true;
  VideoPlayerController? _preview;
  /// Photo drops: the photos in the order they play, and an optional sound track
  final List<File> _photos = [];
  final _photoPages = PageController();
  int _photoIndex = 0;
  File? _sound;
  String? _soundName;
  VideoPlayerController? _soundPlayer;
  List<Map<String, dynamic>> _products = [];
  int? _productId;
  final _caption = TextEditingController();
  double? _progress;
  String? _error;
  bool _rightsConfirmed = false;
  /// Drops of stores Malvoya has not approved yet are saved but not shown in the feed.
  bool _storeApproved = true;

  /// The server accepts drop videos up to 90 seconds (drops.service.ts MAX_VIDEO_SECONDS), up to 10 photos
  /// (MAX_PHOTOS) and a sound track up to 90 seconds (MAX_AUDIO_SECONDS).
  static const _maxVideoSeconds = 90;
  static const _maxPhotos = 10;
  static const _maxSoundSeconds = 90;

  bool get _hasMedia => _isVideo ? _file != null : _photos.isNotEmpty;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _preview?.dispose();
    _soundPlayer?.dispose();
    _photoPages.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final res = await _api.get('/stores/my');
    if (!mounted || !res.ok) return;
    setState(() {
      _storeApproved = res.data['store']?['isVerified'] == true;
      _products = ((res.data['store']?['products'] as List?) ?? [])
          .map((p) => Map<String, dynamic>.from(p))
          .where((p) => p['isAvailable'] != false && p['canBeSold'] != false)
          .toList();
      if (_products.length == 1) _productId = asInt(_products.first['id']);
    });
  }

  Future<void> _pick(bool video, ImageSource source) async {
    final picker = ImagePicker();
    if (!video) return _addPhotos(source);
    final picked = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: _maxVideoSeconds), preferredCameraDevice: CameraDevice.rear);
    if (picked == null || !mounted) return;
    _clearMedia();
    final file = File(picked.path);
    setState(() {
      _file = file;
      _isVideo = true;
      _error = null;
    });
    final c = VideoPlayerController.file(file);
    await c.initialize();
    if (c.value.duration > const Duration(seconds: _maxVideoSeconds)) {
      c.dispose();
      setState(() {
        _file = null;
        _error = tr(context, 'Videos can be up to 90 seconds. Trim it and try again.', 'Video voi olla enintään 90 sekuntia. Lyhennä ja yritä uudelleen.');
      });
      return;
    }
    c.setLooping(true);
    c.play();
    if (mounted) setState(() => _preview = c);
  }

  /// Adds photos to a photo drop (several from the gallery at once, or one from the camera), up to 10 in all.
  Future<void> _addPhotos(ImageSource source) async {
    final picker = ImagePicker();
    final room = _maxPhotos - (_isVideo ? 0 : _photos.length);
    if (room <= 0) return;
    final picked = source == ImageSource.camera
        ? [if (await picker.pickImage(source: source, maxWidth: 1440, maxHeight: 1800, imageQuality: 88) case final x?) x]
        : await picker.pickMultiImage(maxWidth: 1440, maxHeight: 1800, imageQuality: 88, limit: room > 1 ? room : null);
    if (picked.isEmpty || !mounted) return;
    if (_isVideo) _clearMedia();
    setState(() {
      _isVideo = false;
      _photos.addAll(picked.take(room).map((x) => File(x.path)));
      _error = picked.length > room
          ? tr(context, 'A drop can have up to $_maxPhotos photos; the first $room were added.', 'Julkaisussa voi olla enintään $_maxPhotos kuvaa; ensimmäiset $room lisättiin.')
          : null;
    });
  }

  void _removePhoto(int i) {
    setState(() {
      _photos.removeAt(i);
      _photoIndex = _photos.isEmpty ? 0 : _photoIndex.clamp(0, _photos.length - 1);
      if (_photos.isEmpty) _removeSound();
    });
  }

  /// Picks a sound track (music the store owns or has a licence for, or a voice-over) from the phone.
  Future<void> _pickSound() async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked == null || !mounted) return;
    var path = picked.path;
    if (path == null) {
      // Some phones hand over a content link instead of a file: keep a temporary copy to play and upload
      final dir = await Directory.systemTemp.createTemp('drop-sound');
      final copy = File('${dir.path}/${picked.name}');
      await copy.writeAsBytes(await picked.readAsBytes());
      path = copy.path;
    }
    final file = File(path);
    final player = VideoPlayerController.file(file);
    try {
      await player.initialize();
    } catch (_) {
      player.dispose();
      if (mounted) setState(() => _error = tr(context, 'This sound file cannot be played. Choose an MP3, M4A, AAC or WAV file.', 'Tätä äänitiedostoa ei voi toistaa. Valitse MP3-, M4A-, AAC- tai WAV-tiedosto.'));
      return;
    }
    if (player.value.duration > const Duration(seconds: _maxSoundSeconds)) {
      player.dispose();
      if (mounted) setState(() => _error = tr(context, 'A sound track can be up to $_maxSoundSeconds seconds. Trim it and try again.', 'Ääniraita voi olla enintään $_maxSoundSeconds sekuntia. Lyhennä ja yritä uudelleen.'));
      return;
    }
    if (!mounted) return player.dispose();
    _soundPlayer?.dispose();
    player.setLooping(true);
    player.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _sound = file;
      _soundName = picked.name;
      _soundPlayer = player;
      _error = null;
    });
  }

  void _removeSound() {
    _soundPlayer?.dispose();
    _soundPlayer = null;
    _sound = null;
    _soundName = null;
  }

  void _clearMedia() {
    _preview?.dispose();
    _preview = null;
    _file = null;
    _photos.clear();
    _photoIndex = 0;
    _removeSound();
  }

  Future<void> _post() async {
    if (_file == null || _productId == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _progress = 0;
      _error = null;
    });
    _preview?.pause();
    _soundPlayer?.pause();
    try {
      // Every file goes to Cloudinary first (photos in order, then the sound); progress covers them all
      final files = _isVideo ? [_file!] : [..._photos, if (_sound != null) _sound!];
      final uploads = <UploadedMedia>[];
      for (var i = 0; i < files.length; i++) {
        final isSound = !_isVideo && _sound != null && i == files.length - 1;
        uploads.add(await MediaUpload.upload(
          api: _api,
          kind: _isVideo ? 'drop_video' : (isSound ? 'drop_audio' : 'drop_image'),
          file: files[i],
          onProgress: (p) {
            if (mounted) setState(() => _progress = (i + p) / files.length);
          },
        ));
      }
      final photoUploads = _isVideo ? uploads : uploads.take(_photos.length).toList();
      final res = await _api.post('/drops', {
        'productId': _productId,
        'kind': _isVideo ? 'VIDEO' : 'IMAGE',
        'rightsConfirmed': true,
        if (_caption.text.trim().isNotEmpty) 'caption': _caption.text.trim(),
        'upload': photoUploads.first.toProof(),
        if (photoUploads.length > 1) 'images': photoUploads.skip(1).map((u) => u.toProof()).toList(),
        if (!_isVideo && _sound != null) 'audio': uploads.last.toProof(),
      });
      if (!mounted) return;
      if (!res.ok) throw UploadException(res.errorMessage);
      final live = res.data['drop']?['status'] == 'READY';
      MSnack.show(context, !_storeApproved
            ? tr(context, 'Saved — it goes live when your store is approved.', 'Tallennettu — julkaisu näkyy, kun kauppasi on hyväksytty.')
            : live
            ? tr(context, 'Your drop is live!', 'Julkaisusi on julki!')
            : tr(context, 'Posted! The video is being prepared. It usually goes live within a few minutes; you can see its status under Drops.', 'Julkaistu! Videota valmistellaan. Se näkyy yleensä muutaman minuutin kuluessa; näet tilan Julkaisut-välilehdellä.'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _progress != null;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'New drop', 'Uusi julkaisu'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, MSpace.x4l),
        children: [
          AspectRatio(
            aspectRatio: 9 / 16 * 1.6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: MPalette.night,
                child: !_hasMedia
                    ? _chooser()
                    : _isVideo
                        ? (_preview?.value.isInitialized == true
                            ? FittedBox(
                                fit: BoxFit.cover,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox(width: _preview!.value.size.width, height: _preview!.value.size.height, child: VideoPlayer(_preview!)),
                              )
                            : const Center(child: CircularProgressIndicator(color: AppTheme.onPrimary)))
                        : _photoPreview(uploading),
              ),
            ),
          ),
          if (_hasMedia && !uploading)
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (!_isVideo && _photos.length < _maxPhotos)
                  TextButton.icon(
                    onPressed: () => _addPhotos(ImageSource.gallery),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(tr(context, 'Add photos (${_photos.length}/$_maxPhotos)', 'Lisää kuvia (${_photos.length}/$_maxPhotos)')),
                  ),
                TextButton.icon(
                  onPressed: () => setState(_clearMedia),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr(context, 'Start over', 'Aloita alusta')),
                ),
              ],
            ),
          if (!_isVideo && _photos.isNotEmpty) ...[
            const SizedBox(height: MSpace.sm),
            _soundCard(uploading),
          ],
          const SizedBox(height: MSpace.lg),
          DropdownButtonFormField<int>(
            value: _productId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, 'Which product is in the drop?', 'Mikä tuote julkaisussa on?')),
            items: _products
                .map((p) => DropdownMenuItem(value: asInt(p['id']), child: Text(p['name'] ?? '', overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: uploading ? null : (v) => setState(() => _productId = v),
          ),
          if (_products.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr(context, 'Add a product first — every drop sells one of your products.', 'Lisää ensin tuote — jokainen julkaisu myy yhtä tuotettasi.'),
                  style: const TextStyle(color: AppTheme.accent, fontSize: MTextSize.caption)),
            ),
          const SizedBox(height: MSpace.md),
          TextField(
            controller: _caption,
            enabled: !uploading,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr(context, 'Caption', 'Kuvateksti'), hintText: tr(context, 'What makes it special? Fit, material, styling tips', 'Mikä tekee siitä erityisen? Istuvuus, materiaali, tyylivinkit')),
          ),
          const SizedBox(height: MSpace.sm),
          Container(
            padding: const EdgeInsets.all(MSpace.md),
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(MRadius.sm)),
            child: Text(
              tr(context,
                  'Show the real item you are selling. Only use music, logos and people you have permission for: chart songs need a licence for advertising, so use music you made or royalty-free music whose licence allows commercial use. Drops that break the rules or the law are removed, and you are told why.',
                  'Näytä todellinen myytävä tuote. Käytä vain musiikkia, logoja ja ihmisiä, joihin sinulla on lupa: listahittien käyttö mainonnassa vaatii luvan, joten käytä itse tekemääsi musiikkia tai rojaltivapaata musiikkia, jonka lisenssi sallii kaupallisen käytön. Sääntöjen tai lain vastaiset julkaisut poistetaan, ja sinulle kerrotaan syy.'),
              style: const TextStyle(fontSize: MTextSize.caption, height: 1.4, color: AppTheme.primaryDark),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _rightsConfirmed,
            onChanged: uploading ? null : (v) => setState(() => _rightsConfirmed = v ?? false),
            title: Text(
              tr(context,
                  'I made this video, these photos and this sound, or I have permission to use everything in them — including the music, any logos, and everyone who appears in them.',
                  'Tein tämän videon, nämä kuvat ja tämän äänen itse tai minulla on lupa käyttää kaikkea niissä olevaa — myös musiikkia, logoja ja kaikkia niissä näkyviä ihmisiä.'),
              style: const TextStyle(fontSize: MTextSize.label, height: 1.35),
            ),
          ),
          if (!_storeApproved)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.sm),
              child: Text(
                tr(context, 'Your store is in review. Drops you save now go live when Malvoya approves the store.',
                    'Kauppasi on tarkistuksessa. Nyt tallentamasi julkaisut näkyvät, kun Malvoya hyväksyy kaupan.'),
                style: const TextStyle(fontSize: MTextSize.caption, color: MPalette.amberInk),
              ),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: MSpace.md), child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
          const SizedBox(height: MSpace.xl),
          if (uploading) ...[
            LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: MSpace.sm),
            Text('${tr(context, 'Uploading', 'Ladataan')} ${((_progress ?? 0) * 100).round()} %', textAlign: TextAlign.center),
          ] else
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _hasMedia && _productId != null && _rightsConfirmed ? _post : null,
                icon: const Icon(Icons.send_rounded),
                label: Text(_storeApproved ? tr(context, 'Post drop', 'Julkaise') : tr(context, 'Save drop', 'Tallenna julkaisu')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chooser() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_outlined, color: AppTheme.onPrimary.withValues(alpha: 0.7), size: 48),
            const SizedBox(height: MSpace.lg),
            _choice(Icons.fiber_manual_record_rounded, tr(context, 'Record a video (max $_maxVideoSeconds s)', 'Kuvaa video (max $_maxVideoSeconds s)'), () => _pick(true, ImageSource.camera)),
            _choice(Icons.video_library_outlined, tr(context, 'Choose a video', 'Valitse video'), () => _pick(true, ImageSource.gallery)),
            _choice(Icons.photo_library_outlined, tr(context, 'Choose photos (up to $_maxPhotos) and add sound', 'Valitse kuvia (enintään $_maxPhotos) ja lisää ääni'), () => _pick(false, ImageSource.gallery)),
            _choice(Icons.photo_camera_outlined, tr(context, 'Take a photo', 'Ota kuva'), () => _pick(false, ImageSource.camera)),
          ],
        ),
      );

  /// The photos as they will play: swipe through them, remove one, see where you are.
  Widget _photoPreview(bool uploading) => Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _photoPages,
            itemCount: _photos.length,
            onPageChanged: (i) => setState(() => _photoIndex = i),
            itemBuilder: (_, i) => Image.file(_photos[i], fit: BoxFit.cover),
          ),
          if (_photos.length > 1)
            Positioned(
              top: MSpace.md,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Container(
                      width: i == _photoIndex ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.onPrimary.withValues(alpha: i == _photoIndex ? 0.95 : 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          if (!uploading)
            Positioned(
              top: MSpace.sm,
              right: MSpace.sm,
              child: IconButton.filledTonal(
                tooltip: tr(context, 'Remove this photo', 'Poista tämä kuva'),
                onPressed: () => _removePhoto(_photoIndex),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
        ],
      );

  /// The sound of a photo drop: pick a file from the phone, listen to it, remove it.
  Widget _soundCard(bool uploading) {
    final player = _soundPlayer;
    final playing = player?.value.isPlaying == true;
    final seconds = player?.value.duration.inSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: MSpace.sm),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.sm), border: Border.all(color: AppTheme.divider)),
      child: _sound == null
          ? Row(children: [
              const Icon(Icons.music_note_rounded, color: AppTheme.primary),
              const SizedBox(width: MSpace.sm),
              Expanded(
                child: Text(tr(context, 'Add sound: music you own or have a licence for, or your own voice (up to $_maxSoundSeconds s)', 'Lisää ääni: musiikkia, johon sinulla on oikeudet, tai oma äänesi (enintään $_maxSoundSeconds s)'),
                    style: const TextStyle(fontSize: MTextSize.label, height: 1.35)),
              ),
              TextButton(onPressed: uploading ? null : _pickSound, child: Text(tr(context, 'Choose', 'Valitse'))),
            ])
          : Row(children: [
              IconButton(
                tooltip: playing ? tr(context, 'Pause', 'Tauko') : tr(context, 'Listen', 'Kuuntele'),
                onPressed: player == null ? null : () => playing ? player.pause() : player.play(),
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 34),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_soundName ?? tr(context, 'Sound', 'Ääni'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (seconds != null)
                    Text(tr(context, '$seconds s · plays with the photos', '$seconds s · soi kuvien kanssa'),
                        style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
                ]),
              ),
              IconButton(
                tooltip: tr(context, 'Remove sound', 'Poista ääni'),
                onPressed: uploading ? null : () => setState(_removeSound),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
    );
  }

  Widget _choice(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.onPrimary, side: BorderSide(color: AppTheme.onPrimary.withValues(alpha: 0.38)), minimumSize: const Size(240, 46)),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}
