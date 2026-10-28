import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// The sound a store chose for a drop: a track from Malvoya's licensed library (sent as `soundId`), or the
/// store's own file or a voice-over recorded in the app (uploaded as `drop_audio` and sent as `audio`).
class DropSound {
  /// Library track id; null for the store's own sound.
  final int? libraryId;
  final String? title;
  final String? artist;

  /// MP3 address of a library track.
  final String? url;
  final double? durationSec;

  /// The store's own sound file or recording.
  final File? file;
  final String? fileName;
  final bool voiceOver;

  const DropSound.library({required int id, required this.title, this.artist, required this.url, this.durationSec})
      : libraryId = id,
        file = null,
        fileName = null,
        voiceOver = false;

  const DropSound.own({required File this.file, required this.fileName, this.voiceOver = false})
      : libraryId = null,
        title = null,
        artist = null,
        url = null,
        durationSec = null;

  bool get isLibrary => libraryId != null;

  /// One line naming the sound.
  String label(BuildContext context) {
    if (isLibrary) return [title, if ((artist ?? '').isNotEmpty) artist].join(' · ');
    if (voiceOver) return tr(context, 'Your voice-over', 'Oma selostuksesi');
    return fileName ?? tr(context, 'Your sound', 'Oma äänesi');
  }
}

/// "m:ss" for a length in seconds.
String soundLength(num seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "Add sound": choose a track from the Malvoya library, a file from the phone, or record a voice-over.
/// [maxOwnSeconds] is the longest own sound the API accepts.
Future<DropSound?> showAddSoundSheet(BuildContext context, {required int maxOwnSeconds}) {
  return showModalBottomSheet<DropSound>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg))),
    builder: (_) => _AddSoundSheet(maxOwnSeconds: maxOwnSeconds),
  );
}

class _AddSoundSheet extends StatefulWidget {
  final int maxOwnSeconds;
  const _AddSoundSheet({required this.maxOwnSeconds});

  @override
  State<_AddSoundSheet> createState() => _AddSoundSheetState();
}

class _AddSoundSheetState extends State<_AddSoundSheet> {
  int _tab = 0;

  void _done(DropSound sound) => Navigator.pop(context, sound);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(tr(context, 'Add sound', 'Lisää ääni'),
                      style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                ),
                IconButton(
                  tooltip: tr(context, 'Close', 'Sulje'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: MSpace.sm),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.library_music_outlined), label: Text(tr(context, 'Library', 'Kirjasto'))),
                  ButtonSegment(value: 1, icon: const Icon(Icons.audio_file_outlined), label: Text(tr(context, 'Your file', 'Oma tiedosto'))),
                  ButtonSegment(value: 2, icon: const Icon(Icons.mic_none_rounded), label: Text(tr(context, 'Voice-over', 'Selostus'))),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: MSpace.md),
              Expanded(
                child: switch (_tab) {
                  0 => _LibraryTab(onPicked: _done),
                  1 => _FileTab(maxSeconds: widget.maxOwnSeconds, onPicked: _done),
                  _ => _RecordTab(maxSeconds: widget.maxOwnSeconds, onPicked: _done),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _note(String text) => Container(
      padding: const EdgeInsets.all(MSpace.md),
      decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(MRadius.sm)),
      child: Text(text, style: const TextStyle(fontSize: MTextSize.caption, height: 1.4, color: AppTheme.primaryDark)),
    );

/// Licensed tracks from `GET /sounds`: search, listen, pick.
class _LibraryTab extends StatefulWidget {
  final ValueChanged<DropSound> onPicked;
  const _LibraryTab({required this.onPicked});

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  final List<Map<String, dynamic>> _sounds = [];
  int? _nextBefore;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _request = 0;
  VideoPlayerController? _player;
  int? _playingId;
  int? _startingId;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  void _reload() {
    setState(() => _loading = true);
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final request = ++_request;
    if (!reset) setState(() => _loadingMore = true);
    final q = _search.text.trim();
    final res = await _api.get('/sounds', query: {
      'limit': '20',
      if (q.isNotEmpty) 'q': q,
      if (!reset && _nextBefore != null) 'before': '$_nextBefore',
    });
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (!res.ok) {
        _error = res.errorText(context) ?? res.errorMessage;
        return;
      }
      _error = null;
      if (reset) _sounds.clear();
      _sounds.addAll(((res.data['sounds'] as List?) ?? []).map((s) => Map<String, dynamic>.from(s)));
      _nextBefore = asInt(res.data['nextBefore']);
    });
  }

  Future<void> _togglePlay(Map<String, dynamic> s) async {
    final id = asInt(s['id']);
    final url = s['url']?.toString();
    if (id == null || url == null || _startingId != null) return;
    final current = _player;
    if (_playingId == id && current != null) {
      current.value.isPlaying ? await current.pause() : await current.play();
      return;
    }
    _player = null;
    _playingId = null;
    await current?.dispose();
    if (!mounted) return;
    setState(() => _startingId = id);
    final player = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      if (!mounted) return;
      setState(() => _startingId = null);
      MSnack.show(context, tr(context, 'This sound could not be played. Check your connection and try again.', 'Ääntä ei voitu toistaa. Tarkista yhteys ja yritä uudelleen.'));
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    player.addListener(() {
      if (mounted) setState(() {});
    });
    await player.play();
    setState(() {
      _player = player;
      _playingId = id;
      _startingId = null;
    });
  }

  void _pick(Map<String, dynamic> s) {
    final id = asInt(s['id']);
    final url = s['url']?.toString();
    if (id == null || url == null) return;
    HapticFeedback.selectionClick();
    _player?.pause();
    widget.onPicked(DropSound.library(
      id: id,
      title: s['title']?.toString() ?? '',
      artist: s['artist']?.toString(),
      url: url,
      durationSec: (s['durationSec'] as num?)?.toDouble(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: tr(context, 'Search by title or artist', 'Hae nimellä tai esittäjällä'),
          ),
        ),
        const SizedBox(height: MSpace.sm),
        Text(
          tr(context, 'Malvoya holds a licence for every track in the library, so you can use them in your drops.',
              'Malvoyalla on lisenssi jokaiseen kirjaston kappaleeseen, joten voit käyttää niitä julkaisuissasi.'),
          style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: MSpace.sm),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _sounds.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
          const SizedBox(height: MSpace.sm),
          OutlinedButton(onPressed: _reload, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
        ]),
      );
    }
    if (_sounds.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty
              ? tr(context, 'The sound library is empty for now. Use your own file or record a voice-over.', 'Äänikirjasto on vielä tyhjä. Käytä omaa tiedostoa tai nauhoita selostus.')
              : tr(context, 'No sounds match your search.', 'Haullasi ei löytynyt ääniä.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: MSpace.xl),
      children: [
        for (final s in _sounds) _row(s),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accent)),
          ),
        if (_nextBefore != null)
          Center(
            child: _loadingMore
                ? const Padding(padding: EdgeInsets.all(MSpace.md), child: CircularProgressIndicator())
                : TextButton(onPressed: () => _load(), child: Text(tr(context, 'Show more', 'Näytä lisää'))),
          ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final id = asInt(s['id']);
    final playing = _playingId == id && _player?.value.isPlaying == true;
    final starting = _startingId == id;
    final artist = s['artist']?.toString() ?? '';
    final duration = s['durationSec'] as num?;
    final uses = asInt(s['useCount']) ?? 0;
    final details = [
      if (artist.isNotEmpty) artist,
      if (duration != null) soundLength(duration),
      if (uses > 0) tr(context, '$uses drops', '$uses julkaisua'),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: starting
          ? const SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
          : IconButton(
              tooltip: playing ? tr(context, 'Pause', 'Tauko') : tr(context, 'Listen', 'Kuuntele'),
              onPressed: () => _togglePlay(s),
              icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 34),
            ),
      title: Text(s['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: details.isEmpty ? null : Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: MTextSize.caption)),
      trailing: FilledButton.tonal(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
        onPressed: () => _pick(s),
        child: Text(tr(context, 'Use', 'Käytä')),
      ),
    );
  }
}

/// A sound file from the phone: music the store owns or has a commercial licence for.
class _FileTab extends StatefulWidget {
  final int maxSeconds;
  final ValueChanged<DropSound> onPicked;
  const _FileTab({required this.maxSeconds, required this.onPicked});

  @override
  State<_FileTab> createState() => _FileTabState();
}

class _FileTabState extends State<_FileTab> {
  bool _busy = false;
  String? _error;

  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
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
      if (!mounted) return;
      widget.onPicked(DropSound.own(file: File(path), fileName: picked.name));
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'The file could not be opened. Try another file.', 'Tiedostoa ei voitu avata. Kokeile toista tiedostoa.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _note(tr(context,
            'Only use music you made yourself or music whose licence allows commercial use, such as advertising. Chart songs need a licence for advertising. MP3, M4A, AAC or WAV, up to ${widget.maxSeconds} s. Your own sounds are not shared with other stores.',
            'Käytä vain itse tekemääsi musiikkia tai musiikkia, jonka lisenssi sallii kaupallisen käytön, kuten mainonnan. Listahittien käyttö mainonnassa vaatii luvan. MP3, M4A, AAC tai WAV, enintään ${widget.maxSeconds} s. Omia ääniäsi ei jaeta muille kaupoille.')),
        const SizedBox(height: MSpace.lg),
        Center(
          child: FilledButton.icon(
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(tr(context, 'Choose a sound file', 'Valitse äänitiedosto')),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.md),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

/// A voice-over recorded in the app (AAC in an .m4a file), up to [maxSeconds].
class _RecordTab extends StatefulWidget {
  final int maxSeconds;
  final ValueChanged<DropSound> onPicked;
  const _RecordTab({required this.maxSeconds, required this.onPicked});

  @override
  State<_RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<_RecordTab> {
  final _recorder = AudioRecorder();
  final _clock = Stopwatch();
  Timer? _ticker;
  bool _recording = false;
  bool _starting = false;
  File? _result;
  VideoPlayerController? _player;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _player?.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      // The phone asks for the microphone the first time; the text above the button says why
      final allowed = await _recorder.hasPermission();
      if (!mounted) return;
      if (!allowed) {
        setState(() => _error = tr(context,
            'Malvoya Store cannot use the microphone. To record a voice-over, allow the microphone for Malvoya Store in your phone\'s settings (Apps > Malvoya Store > Permissions), then try again.',
            'Malvoya Store ei voi käyttää mikrofonia. Salli mikrofoni Malvoya Storelle puhelimen asetuksissa (Sovellukset > Malvoya Store > Käyttöoikeudet) ja yritä sitten uudelleen.'));
        return;
      }
      final old = _player;
      _player = null;
      _result = null;
      await old?.dispose();
      final dir = await Directory.systemTemp.createTemp('voice-over');
      final path = '${dir.path}/voice-over.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, sampleRate: 44100, bitRate: 128000), path: path);
      HapticFeedback.mediumImpact();
      _clock
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_clock.elapsed >= Duration(seconds: widget.maxSeconds)) {
          _stop();
        } else if (mounted) {
          setState(() {});
        }
      });
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'Recording could not start. Close other apps that use the microphone and try again.', 'Nauhoitus ei käynnistynyt. Sulje muut mikrofonia käyttävät sovellukset ja yritä uudelleen.'));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    _recording = false;
    HapticFeedback.mediumImpact();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    if (path == null || _clock.elapsed < const Duration(seconds: 1)) {
      setState(() => _error = tr(context, 'The recording was too short. Hold on a little longer and try again.', 'Nauhoitus oli liian lyhyt. Puhu hieman pidempään ja yritä uudelleen.'));
      return;
    }
    final file = File(path);
    final player = VideoPlayerController.file(file);
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      if (mounted) setState(() => _error = tr(context, 'The recording could not be played. Try again.', 'Nauhoitusta ei voitu toistaa. Yritä uudelleen.'));
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    player.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _result = file;
      _player = player;
    });
  }

  void _use() {
    final file = _result;
    if (file == null) return;
    _player?.pause();
    widget.onPicked(DropSound.own(file: file, fileName: 'voice-over.m4a', voiceOver: true));
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _clock.elapsed.inSeconds;
    final player = _player;
    final playing = player?.value.isPlaying == true;
    return ListView(
      children: [
        _note(tr(context,
            'Tell shoppers about the item in your own words, up to ${widget.maxSeconds} seconds. The microphone is used only while you record, and your phone asks for permission the first time.',
            'Kerro tuotteesta omin sanoin, enintään ${widget.maxSeconds} sekuntia. Mikrofonia käytetään vain nauhoituksen ajan, ja puhelin kysyy lupaa ensimmäisellä kerralla.')),
        const SizedBox(height: MSpace.xl),
        Center(
          child: Text(
            _recording ? '${soundLength(elapsed)} / ${soundLength(widget.maxSeconds)}' : (player != null ? soundLength(player.value.duration.inMilliseconds / 1000) : soundLength(0)),
            style: const TextStyle(fontSize: MTextSize.displayM, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
        if (_recording) ...[
          const SizedBox(height: MSpace.sm),
          LinearProgressIndicator(value: _clock.elapsed.inMilliseconds / (widget.maxSeconds * 1000), minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ],
        const SizedBox(height: MSpace.lg),
        Center(
          child: _recording
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(tr(context, 'Stop', 'Lopeta')),
                )
              : FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: const Icon(Icons.mic_rounded),
                  label: Text(_result == null ? tr(context, 'Start recording', 'Aloita nauhoitus') : tr(context, 'Record again', 'Nauhoita uudelleen')),
                ),
        ),
        if (_recording)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm),
            child: Text(tr(context, 'Recording', 'Nauhoitetaan'), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
          ),
        if (player != null && !_recording) ...[
          const SizedBox(height: MSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: playing ? tr(context, 'Pause', 'Tauko') : tr(context, 'Listen', 'Kuuntele'),
                onPressed: () async {
                  if (playing) return player.pause();
                  if (player.value.position >= player.value.duration) await player.seekTo(Duration.zero);
                  await player.play();
                },
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 40),
              ),
              const SizedBox(width: MSpace.md),
              FilledButton(onPressed: _use, child: Text(tr(context, 'Use this recording', 'Käytä tätä nauhoitusta'))),
            ],
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.md),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
