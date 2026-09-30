import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/media_upload.dart';
import '../core/strings.dart';

/// Record or pick a short video (or a photo), link it to one of your products and post it.
class CreateDropScreen extends StatefulWidget {
  const CreateDropScreen({super.key});

  @override
  State<CreateDropScreen> createState() => _CreateDropScreenState();
}

class _CreateDropScreenState extends State<CreateDropScreen> {
  File? _file;
  bool _isVideo = true;
  VideoPlayerController? _preview;
  List<Map<String, dynamic>> _products = [];
  int? _productId;
  final _caption = TextEditingController();
  double? _progress;
  String? _error;
  bool _rightsConfirmed = false;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _preview?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final res = await _api.get('/stores/my');
    if (!mounted || !res.ok) return;
    setState(() {
      _products = ((res.data['store']?['products'] as List?) ?? [])
          .map((p) => Map<String, dynamic>.from(p))
          .where((p) => p['isAvailable'] != false && p['canBeSold'] != false)
          .toList();
      if (_products.length == 1) _productId = asInt(_products.first['id']);
    });
  }

  Future<void> _pick(bool video, ImageSource source) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60), preferredCameraDevice: CameraDevice.rear)
        : await picker.pickImage(source: source, maxWidth: 1440, maxHeight: 1800, imageQuality: 88);
    if (picked == null || !mounted) return;
    _preview?.dispose();
    _preview = null;
    final file = File(picked.path);
    setState(() {
      _file = file;
      _isVideo = video;
      _error = null;
    });
    if (video) {
      final c = VideoPlayerController.file(file);
      await c.initialize();
      if (c.value.duration > const Duration(seconds: 90)) {
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
  }

  Future<void> _post() async {
    if (_file == null || _productId == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _progress = 0;
      _error = null;
    });
    _preview?.pause();
    try {
      final media = await MediaUpload.upload(
        api: _api,
        kind: _isVideo ? 'drop_video' : 'drop_image',
        file: _file!,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final res = await _api.post('/drops', {
        'productId': _productId,
        'kind': _isVideo ? 'VIDEO' : 'IMAGE',
        'rightsConfirmed': true,
        if (_caption.text.trim().isNotEmpty) 'caption': _caption.text.trim(),
        'upload': media.toProof(),
      });
      if (!mounted) return;
      if (!res.ok) throw UploadException(res.error!);
      final live = res.data['drop']?['status'] == 'READY';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(live
            ? tr(context, 'Your drop is live!', 'Julkaisusi on julki!')
            : tr(context, 'Posted! The video is being prepared and goes live in about a minute.', 'Julkaistu! Videota valmistellaan, ja se näkyy noin minuutin kuluttua.')),
      ));
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          AspectRatio(
            aspectRatio: 9 / 16 * 1.6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: Colors.black,
                child: _file == null
                    ? _chooser()
                    : _isVideo
                        ? (_preview?.value.isInitialized == true
                            ? FittedBox(
                                fit: BoxFit.cover,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox(width: _preview!.value.size.width, height: _preview!.value.size.height, child: VideoPlayer(_preview!)),
                              )
                            : const Center(child: CircularProgressIndicator(color: Colors.white)))
                        : Image.file(_file!, fit: BoxFit.cover),
              ),
            ),
          ),
          if (_file != null && !uploading)
            TextButton.icon(
              onPressed: () {
                _preview?.dispose();
                setState(() {
                  _preview = null;
                  _file = null;
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr(context, 'Choose another', 'Valitse toinen')),
            ),
          const SizedBox(height: 16),
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
                  style: const TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            enabled: !uploading,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr(context, 'Caption', 'Kuvateksti'), hintText: tr(context, 'What makes it special? Fit, material, styling tips', 'Mikä tekee siitä erityisen? Istuvuus, materiaali, tyylivinkit')),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
            child: Text(
              tr(context,
                  'Show the real item you are selling. Only use music, logos and people you have permission for. Drops that break the rules or the law are removed, and you are told why.',
                  'Näytä todellinen myytävä tuote. Käytä vain musiikkia, logoja ja ihmisiä, joihin sinulla on lupa. Sääntöjen tai lain vastaiset julkaisut poistetaan, ja sinulle kerrotaan syy.'),
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.primaryDark),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _rightsConfirmed,
            onChanged: uploading ? null : (v) => setState(() => _rightsConfirmed = v ?? false),
            title: Text(
              tr(context,
                  'I made this video or photo, or I have permission to use everything in it — including the music, any logos, and everyone who appears in it.',
                  'Tein tämän videon tai kuvan itse tai minulla on lupa käyttää kaikkea siinä olevaa — myös musiikkia, logoja ja kaikkia siinä näkyviä ihmisiä.'),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
          const SizedBox(height: 20),
          if (uploading) ...[
            LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 8),
            Text('${tr(context, 'Uploading', 'Ladataan')} ${((_progress ?? 0) * 100).round()} %', textAlign: TextAlign.center),
          ] else
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _file != null && _productId != null && _rightsConfirmed ? _post : null,
                icon: const Icon(Icons.send_rounded),
                label: Text(tr(context, 'Post drop', 'Julkaise')),
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
            const Icon(Icons.videocam_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            _choice(Icons.fiber_manual_record_rounded, tr(context, 'Record a video (max 60 s)', 'Kuvaa video (max 60 s)'), () => _pick(true, ImageSource.camera)),
            _choice(Icons.video_library_outlined, tr(context, 'Choose a video', 'Valitse video'), () => _pick(true, ImageSource.gallery)),
            _choice(Icons.photo_outlined, tr(context, 'Use a photo instead', 'Käytä kuvaa'), () => _pick(false, ImageSource.gallery)),
          ],
        ),
      );

  Widget _choice(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size(240, 46)),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}
