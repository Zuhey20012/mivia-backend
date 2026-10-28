import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/media_upload.dart';
import 'drop_sound_sheet.dart';

/// Record or pick a short video, or up to 10 photos, add a sound (a licensed track from the Malvoya library,
/// a file from the phone or a voice-over recorded here), link it to one of your products and post it.
/// Videos can be trimmed (playback plays only that part; the file is not cut) and keep their own sound quietly
/// under the added one (MIX) or play only the added sound (REPLACE).
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

  /// The part of the video that plays, in seconds (the whole video until the store changes it)
  RangeValues? _trim;
  Timer? _loopTimer;
  bool _checkingLoop = false;
  bool _scrubbing = false;
  bool _previewPaused = false;
  DateTime _lastSeek = DateTime(2000);

  /// Photo drops: the photos in the order they play
  final List<File> _photos = [];
  final _photoPages = PageController();
  int _photoIndex = 0;

  /// The added sound (any drop) and how it plays with a video's own sound
  DropSound? _sound;
  VideoPlayerController? _soundPlayer;
  String _soundMode = 'MIX';

  List<Map<String, dynamic>> _products = [];
  int? _productId;
  final _caption = TextEditingController();
  double? _progress;
  String? _error;
  bool _rightsConfirmed = false;

  /// Drops of stores Malvoya has not approved yet are saved but not shown in the feed.
  bool _storeApproved = true;

  /// The server accepts drop videos up to 90 seconds (drops.service.ts MAX_VIDEO_SECONDS), up to 10 photos
  /// (MAX_PHOTOS) and an own sound track up to 90 seconds (MAX_AUDIO_SECONDS). A trimmed video plays at least 3 s.
  static const _maxVideoSeconds = 90;
  static const _maxPhotos = 10;
  static const _maxSoundSeconds = 90;
  static const _minTrimSeconds = 3.0;

  /// How loud the video's own sound plays under an added sound (MIX), as in the customer app.
  static const _mixVideoVolume = 0.3;

  bool get _hasMedia => _isVideo ? _file != null : _photos.isNotEmpty;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  double get _videoSeconds => (_preview?.value.duration.inMilliseconds ?? 0) / 1000;

  bool get _canTrim => _isVideo && _preview?.value.isInitialized == true && _videoSeconds > _minTrimSeconds + 0.1;

  bool get _trimChanged {
    final t = _trim;
    return _isVideo && t != null && (t.start > 0.05 || t.end < _videoSeconds - 0.05);
  }

  Duration get _trimStart => Duration(milliseconds: ((_trim?.start ?? 0) * 1000).round());

  Duration get _trimEnd => _trim == null ? (_preview?.value.duration ?? Duration.zero) : Duration(milliseconds: (_trim!.end * 1000).round());

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
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
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) {
        setState(() {
          _file = null;
          _error = tr(context, 'This video cannot be played. Choose another video.', 'Tätä videota ei voi toistaa. Valitse toinen video.');
        });
      }
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    if (c.value.duration > const Duration(seconds: _maxVideoSeconds)) {
      await c.dispose();
      setState(() {
        _file = null;
        _error = tr(context, 'Videos can be up to 90 seconds. Trim it and try again.', 'Video voi olla enintään 90 sekuntia. Lyhennä ja yritä uudelleen.');
      });
      return;
    }
    // Looping is done here (not by the player) so a trimmed preview loops only the chosen part
    await c.setLooping(false);
    setState(() {
      _preview = c;
      _trim = RangeValues(0, c.value.duration.inMilliseconds / 1000);
      _previewPaused = false;
    });
    _applyVolumes();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 150), (_) => _checkLoop());
    await c.play();
  }

  /// Starts the video preview (and the added sound) again at the start of the trimmed part.
  Future<void> _restartPreview() async {
    final c = _preview;
    if (c == null) return;
    await c.seekTo(_trimStart);
    await _soundPlayer?.seekTo(Duration.zero);
    if (_previewPaused || _scrubbing || !mounted) return;
    await c.play();
    await _soundPlayer?.play();
  }

  /// Loops the preview inside the trimmed part, with the sound restarting together with the video.
  Future<void> _checkLoop() async {
    final c = _preview;
    if (c == null || !c.value.isInitialized || _previewPaused || _scrubbing || _checkingLoop) return;
    _checkingLoop = true;
    try {
      final pos = await c.position ?? c.value.position;
      final ended = !c.value.isPlaying && pos >= c.value.duration - const Duration(milliseconds: 300);
      if (pos >= _trimEnd - const Duration(milliseconds: 80) || ended) await _restartPreview();
    } catch (_) {
      // The controller was disposed while checking
    } finally {
      _checkingLoop = false;
    }
  }

  Future<void> _togglePreview() async {
    final c = _preview;
    if (c == null) return;
    setState(() => _previewPaused = !_previewPaused);
    if (_previewPaused) {
      await c.pause();
      await _soundPlayer?.pause();
    } else {
      await _restartPreview();
    }
  }

  void _applyVolumes() {
    _preview?.setVolume(_sound == null ? 1 : (_soundMode == 'MIX' ? _mixVideoVolume : 0));
    _soundPlayer?.setVolume(1);
  }

  void _onTrimStart(RangeValues _) {
    _scrubbing = true;
    _preview?.pause();
    _soundPlayer?.pause();
  }

  void _onTrimChanged(RangeValues v) {
    final old = _trim ?? v;
    final total = _videoSeconds;
    var start = v.start;
    var end = v.end;
    final movedStart = (start - old.start).abs() >= (end - old.end).abs();
    if (end - start < _minTrimSeconds) {
      if (movedStart) {
        start = math.max(0.0, end - _minTrimSeconds);
        end = math.max(end, math.min(total, start + _minTrimSeconds));
      } else {
        end = math.min(total, start + _minTrimSeconds);
        start = math.min(start, math.max(0.0, end - _minTrimSeconds));
      }
    }
    setState(() => _trim = RangeValues(start, end));
    // Show the frame under the moving handle (at most every 120 ms, seeking is not free)
    final now = DateTime.now();
    if (now.difference(_lastSeek) > const Duration(milliseconds: 120)) {
      _lastSeek = now;
      _preview?.seekTo(Duration(milliseconds: ((movedStart ? start : end) * 1000).round()));
    }
  }

  void _onTrimEnd(RangeValues _) {
    _scrubbing = false;
    _restartPreview();
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

  /// "Add sound": the library, a file from the phone, or a voice-over recorded here.
  Future<void> _openSoundSheet() async {
    final wasPaused = _previewPaused;
    _previewPaused = true;
    await _preview?.pause();
    await _soundPlayer?.pause();
    if (!mounted) return;
    final picked = await showAddSoundSheet(context, maxOwnSeconds: _maxSoundSeconds);
    if (!mounted) return;
    if (picked != null) await _useSound(picked);
    if (!mounted) return;
    setState(() => _previewPaused = wasPaused);
    if (!wasPaused && _isVideo) await _restartPreview();
  }

  /// Loads the chosen sound so it can be previewed, and checks an own sound's length.
  Future<void> _useSound(DropSound sound) async {
    final player = sound.isLibrary ? VideoPlayerController.networkUrl(Uri.parse(sound.url!)) : VideoPlayerController.file(sound.file!);
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() => _error = sound.isLibrary
            ? tr(context, 'This sound could not be loaded. Check your connection and try again.', 'Ääntä ei voitu ladata. Tarkista yhteys ja yritä uudelleen.')
            : tr(context, 'This sound file cannot be played. Choose an MP3, M4A, AAC or WAV file.', 'Tätä äänitiedostoa ei voi toistaa. Valitse MP3-, M4A-, AAC- tai WAV-tiedosto.'));
      }
      return;
    }
    if (!sound.isLibrary && player.value.duration > const Duration(seconds: _maxSoundSeconds)) {
      await player.dispose();
      if (mounted) {
        setState(() => _error = tr(context, 'A sound track can be up to $_maxSoundSeconds seconds. Trim it and try again.', 'Ääniraita voi olla enintään $_maxSoundSeconds sekuntia. Lyhennä ja yritä uudelleen.'));
      }
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    _soundPlayer?.dispose();
    await player.setLooping(true);
    player.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _sound = sound;
      _soundPlayer = player;
      _error = null;
    });
    _applyVolumes();
  }

  void _removeSound() {
    _soundPlayer?.dispose();
    _soundPlayer = null;
    _sound = null;
    _soundMode = 'MIX';
    _applyVolumes();
  }

  void _clearMedia() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _preview?.dispose();
    _preview = null;
    _trim = null;
    _previewPaused = false;
    _file = null;
    _photos.clear();
    _photoIndex = 0;
    _removeSound();
  }

  /// The trimmed part to send, in tenths of a second inside what Cloudinary measured; null = the whole video.
  ({double start, double end})? _trimToSend(UploadedMedia video) {
    final t = _trim;
    if (!_trimChanged || t == null) return null;
    final total = math.min(_videoSeconds, video.durationSec ?? _videoSeconds);
    final endTenths = (math.min(t.end, total) * 10).floor();
    if (endTenths < (_minTrimSeconds * 10).round()) return null;
    final startTenths = math.max(0, math.min((t.start * 10).round(), endTenths - (_minTrimSeconds * 10).round()));
    return (start: startTenths / 10, end: endTenths / 10);
  }

  Future<void> _post() async {
    if (!_hasMedia || _productId == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _progress = 0;
      _error = null;
      _previewPaused = true;
    });
    _preview?.pause();
    _soundPlayer?.pause();
    try {
      // Every file goes to Cloudinary first (the video or the photos in order, then an own sound); one progress
      // bar covers them all. A library sound is not uploaded: it is sent as its id.
      final ownSound = _sound?.file;
      final mediaFiles = _isVideo ? [_file!] : [..._photos];
      final files = [...mediaFiles, if (ownSound != null) ownSound];
      final uploads = <UploadedMedia>[];
      for (var i = 0; i < files.length; i++) {
        final isSound = ownSound != null && i == files.length - 1;
        uploads.add(await MediaUpload.upload(
          api: _api,
          kind: isSound ? 'drop_audio' : (_isVideo ? 'drop_video' : 'drop_image'),
          file: files[i],
          onProgress: (p) {
            if (mounted) setState(() => _progress = (i + p) / files.length);
          },
        ));
      }
      final mediaUploads = uploads.take(mediaFiles.length).toList();
      final soundUpload = ownSound != null ? uploads.last : null;
      final trim = _isVideo ? _trimToSend(mediaUploads.first) : null;
      final res = await _api.post('/drops', {
        'productId': _productId,
        'kind': _isVideo ? 'VIDEO' : 'IMAGE',
        'rightsConfirmed': true,
        if (_caption.text.trim().isNotEmpty) 'caption': _caption.text.trim(),
        'upload': mediaUploads.first.toProof(),
        if (!_isVideo && mediaUploads.length > 1) 'images': mediaUploads.skip(1).map((u) => u.toProof()).toList(),
        if (_sound?.libraryId != null) 'soundId': _sound!.libraryId,
        if (soundUpload != null) 'audio': soundUpload.toProof(),
        if (_isVideo && _sound != null) 'soundMode': _soundMode,
        if (trim != null) ...{'trimStartSec': trim.start, 'trimEndSec': trim.end},
      });
      if (!mounted) return;
      if (!res.ok) throw UploadException(res.errorText(context) ?? res.errorMessage);
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
                        ? (_preview?.value.isInitialized == true ? _videoPreview(uploading) : const Center(child: CircularProgressIndicator(color: AppTheme.onPrimary)))
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
          if (_canTrim) ...[
            const SizedBox(height: MSpace.sm),
            _trimCard(uploading),
          ],
          if (_hasMedia) ...[
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
                  'Show the real item you are selling. Only use music, logos and people you have permission for: chart songs need a licence for advertising, so use music you made or royalty-free music whose licence allows commercial use. Tracks in the Malvoya sound library are licensed by Malvoya for drops. Drops that break the rules or the law are removed, and you are told why.',
                  'Näytä todellinen myytävä tuote. Käytä vain musiikkia, logoja ja ihmisiä, joihin sinulla on lupa: listahittien käyttö mainonnassa vaatii luvan, joten käytä itse tekemääsi musiikkia tai rojaltivapaata musiikkia, jonka lisenssi sallii kaupallisen käytön. Malvoyan äänikirjaston kappaleisiin Malvoyalla on lisenssi julkaisuja varten. Sääntöjen tai lain vastaiset julkaisut poistetaan, ja sinulle kerrotaan syy.'),
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
                  'I made this video, these photos and any sound of my own, or I have permission to use everything in them — including the music, any logos, and everyone who appears in them.',
                  'Tein tämän videon, nämä kuvat ja oman ääneni itse tai minulla on lupa käyttää kaikkea niissä olevaa — myös musiikkia, logoja ja kaikkia niissä näkyviä ihmisiä.'),
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

  /// The video as it will play (trimmed part, with the added sound); tap to pause or play.
  Widget _videoPreview(bool uploading) {
    final c = _preview!;
    return Semantics(
      button: true,
      label: _previewPaused ? tr(context, 'Play preview', 'Toista esikatselu') : tr(context, 'Pause preview', 'Keskeytä esikatselu'),
      child: GestureDetector(
        onTap: uploading ? null : _togglePreview,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            ),
            if (_previewPaused && !uploading)
              Center(child: Icon(Icons.play_circle_fill_rounded, size: 64, color: AppTheme.onPrimary.withValues(alpha: 0.9))),
          ],
        ),
      ),
    );
  }

  /// Which part of the video plays: drag the handles; the preview loops the chosen part.
  Widget _trimCard(bool uploading) {
    final total = _videoSeconds;
    final t = _trim ?? RangeValues(0, total);
    String s(double v) => '${v.toStringAsFixed(1)} s';
    return Container(
      padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.sm, MSpace.md, MSpace.sm),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.sm), border: Border.all(color: AppTheme.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.content_cut_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: MSpace.sm),
            Expanded(
              child: Text(tr(context, 'Trim', 'Rajaa'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (_trimChanged && !uploading)
              TextButton(
                onPressed: () {
                  setState(() => _trim = RangeValues(0, total));
                  _restartPreview();
                },
                child: Text(tr(context, 'Whole video', 'Koko video')),
              ),
          ]),
          RangeSlider(
            values: t,
            min: 0,
            max: total,
            onChangeStart: uploading ? null : _onTrimStart,
            onChanged: uploading ? null : _onTrimChanged,
            onChangeEnd: uploading ? null : _onTrimEnd,
          ),
          Text(
            _trimChanged
                ? tr(context, 'Plays ${s(t.start)} – ${s(t.end)} (${s(t.end - t.start)} of ${s(total)}). The video file is not cut.',
                    'Toistetaan ${s(t.start)} – ${s(t.end)} (${s(t.end - t.start)} / ${s(total)}). Videotiedostoa ei leikata.')
                : tr(context, 'Plays the whole video (${s(total)}). Drag the handles to play only part of it, at least 3 s.',
                    'Koko video toistetaan (${s(total)}). Vedä kahvoista, jos haluat toistaa vain osan, vähintään 3 s.'),
            style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

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

  /// The drop's added sound: add one, listen (photos; a video previews it with the video), change, remove, and for
  /// videos choose whether the video's own sound plays quietly under it.
  Widget _soundCard(bool uploading) {
    final sound = _sound;
    final player = _soundPlayer;
    final playing = player?.value.isPlaying == true;
    final seconds = player?.value.duration.inMilliseconds;
    final decoration = BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.sm), border: Border.all(color: AppTheme.divider));
    if (sound == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: MSpace.sm),
        decoration: decoration,
        child: Row(children: [
          const Icon(Icons.music_note_rounded, color: AppTheme.primary),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: Text(
              _isVideo
                  ? tr(context, 'Add sound: a track from the Malvoya library, your own file or a voice-over. The video keeps its own sound unless you add one.',
                      'Lisää ääni: kappale Malvoyan kirjastosta, oma tiedosto tai selostus. Videossa on oma äänensä, ellet lisää toista.')
                  : tr(context, 'Add sound: a track from the Malvoya library, your own file or a voice-over (up to $_maxSoundSeconds s)',
                      'Lisää ääni: kappale Malvoyan kirjastosta, oma tiedosto tai selostus (enintään $_maxSoundSeconds s)'),
              style: const TextStyle(fontSize: MTextSize.label, height: 1.35),
            ),
          ),
          TextButton(onPressed: uploading ? null : _openSoundSheet, child: Text(tr(context, 'Add sound', 'Lisää ääni'))),
        ]),
      );
    }
    final source = sound.isLibrary
        ? tr(context, 'Malvoya library', 'Malvoyan kirjasto')
        : sound.voiceOver
            ? tr(context, 'Recorded here', 'Nauhoitettu sovelluksessa')
            : tr(context, 'Your file', 'Oma tiedosto');
    final details = [source, if (seconds != null && seconds > 0) soundLength(seconds / 1000)].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: MSpace.sm),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            if (_isVideo)
              const Padding(padding: EdgeInsets.symmetric(horizontal: MSpace.md), child: Icon(Icons.music_note_rounded, color: AppTheme.primary))
            else
              IconButton(
                tooltip: playing ? tr(context, 'Pause', 'Tauko') : tr(context, 'Listen', 'Kuuntele'),
                onPressed: player == null ? null : () => playing ? player.pause() : player.play(),
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 34),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sound.label(context), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
              ]),
            ),
            IconButton(
              tooltip: tr(context, 'Change sound', 'Vaihda ääni'),
              onPressed: uploading ? null : _openSoundSheet,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
            IconButton(
              tooltip: tr(context, 'Remove sound', 'Poista ääni'),
              onPressed: uploading ? null : () => setState(_removeSound),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          if (_isVideo) ...[
            const SizedBox(height: MSpace.sm),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'MIX', label: Text(tr(context, 'Mix with the video\'s sound', 'Sekoita videon ääneen'), textAlign: TextAlign.center)),
                ButtonSegment(value: 'REPLACE', label: Text(tr(context, 'Only the added sound', 'Vain lisätty ääni'), textAlign: TextAlign.center)),
              ],
              selected: {_soundMode},
              onSelectionChanged: uploading
                  ? null
                  : (s) {
                      setState(() => _soundMode = s.first);
                      _applyVolumes();
                    },
            ),
            const SizedBox(height: MSpace.xs),
            Text(
              _soundMode == 'MIX'
                  ? tr(context, 'The video\'s own sound plays quietly under the added sound. Tap the video to pause the preview.',
                      'Videon oma ääni soi hiljaa lisätyn äänen alla. Napauta videota keskeyttääksesi esikatselun.')
                  : tr(context, 'Only the added sound plays; the video\'s own sound is muted. Tap the video to pause the preview.',
                      'Vain lisätty ääni soi; videon oma ääni on mykistetty. Napauta videota keskeyttääksesi esikatselun.'),
              style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
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
