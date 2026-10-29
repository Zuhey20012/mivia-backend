import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../widgets/error_banner.dart';
import 'create_drop.dart';
import 'drop_comments.dart';
import 'live/go_live_screen.dart';
import 'live/live_common.dart';

/// Your drops with their real numbers: views, likes, comments, shares and how many watched to the end.
class DropsManager extends StatefulWidget {
  const DropsManager({super.key});

  @override
  State<DropsManager> createState() => DropsManagerState();
}

class DropsManagerState extends State<DropsManager> {
  List<Map<String, dynamic>> _drops = [];
  bool _loading = true;
  String? _error;

  /// The store's live that is still on (`GET /stores/my/live`), e.g. after the app was closed mid-live.
  Map<String, dynamic>? _currentLive;
  bool _endingLive = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final (res, live) = await (api.get('/drops/mine'), api.get('/stores/my/live')).wait;
    if (!mounted) return;
    // A server without live shopping answers 404 here; the "Go live" card still opens the set-up
    if (live.ok) _currentLive = currentLiveOf(live.data);
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.error;
      if (res.ok) _drops = ((res.data['drops'] as List?) ?? []).map((d) => Map<String, dynamic>.from(d)).toList();
    });
  }

  void _retry() {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    load();
  }

  Future<void> goLive() async {
    Haptics.medium();
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const GoLiveScreen()));
    if (mounted) load();
  }

  Future<void> _endCurrentLive() async {
    final live = _currentLive;
    if (live == null || _endingLive) return;
    if (!await confirmEndLive(context, title: '${live['title'] ?? ''}') || !mounted) return;
    setState(() => _endingLive = true);
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/live/${live['id']}/end');
    if (!mounted) return;
    setState(() => _endingLive = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    MSnack.success(context, tr(context, 'The live has ended.', 'Livelähetys on päättynyt.'));
    load();
  }

  Future<void> create() async {
    final posted = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreateDropScreen()));
    if (posted == true) load();
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Delete this drop?', 'Poistetaanko julkaisu?')),
        content: Text(tr(context, 'The video is removed from Malvoya for good.', 'Video poistetaan Malvoyasta pysyvästi.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep', 'Pidä'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Delete', 'Poista'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).delete('/drops/${d['id']}');
    if (!mounted) return;
    if (!res.ok) MSnack.show(context, res.errorMessage);
    load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const MSkeletonList(thumbnail: true, lines: 4, padding: EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 100));
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 100),
        children: [
          _liveCard(),
          const SizedBox(height: MSpace.lg),
          if (_error != null && _drops.isEmpty)
            MStateMessage.error(scrollable: false, message: _error, onRetry: _retry, top: 24)
          else ...[
            _summary(),
            const SizedBox(height: MSpace.lg),
            if (_error != null) ErrorBanner(message: _error!, onRetry: _retry),
          ],
          if (_drops.isEmpty && _error == null)
            MStateMessage(scrollable: false, icon: Icons.video_camera_back_outlined,
              top: 24,
              message: tr(context, 'Show your items in a short video. Drops appear in the customer app\'s Drops feed with a buy button.',
                  'Esittele tuotteitasi lyhyellä videolla. Julkaisut näkyvät asiakkaiden Drops-syötteessä osta-painikkeen kanssa.'),
              action: Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(onPressed: create, icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'Create your first drop', 'Luo ensimmäinen julkaisu'))),
              ]),
            ),
          for (final d in _drops) _card(d),
        ],
      ),
    );
  }

  /// "Go live": show products on camera to nearby customers. While a live is still on (the app was
  /// closed during it), the card says so and can end it.
  Widget _liveCard() {
    final live = _currentLive;
    return Container(
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: live != null ? AppTheme.dangerLight : AppTheme.lilac, borderRadius: BorderRadius.circular(MRadius.md)),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: live != null ? AppTheme.danger : AppTheme.surface, shape: BoxShape.circle),
          child: Icon(Icons.sensors_rounded, color: live != null ? AppTheme.onPrimary : AppTheme.textPrimary),
        ),
        const SizedBox(width: MSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              live != null ? tr(context, 'You are live: ${live['title'] ?? ''}', 'Lähetyksesi on käynnissä: ${live['title'] ?? ''}') : tr(context, 'Go live', 'Aloita livelähetys'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              live != null
                  ? tr(context, 'Continue it from Go live, or end it here.', 'Jatka sitä kohdasta Aloita livelähetys tai lopeta se tästä.')
                  : tr(context, 'Show your products on camera. Nearby customers watch, chat and buy. Not recorded.',
                      'Esittele tuotteitasi kameralla. Lähellä olevat asiakkaat katsovat, keskustelevat ja ostavat. Ei tallenneta.'),
              style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.35),
            ),
            const SizedBox(height: MSpace.sm),
            Wrap(spacing: MSpace.sm, runSpacing: MSpace.xs, children: [
              FilledButton.icon(
                onPressed: goLive,
                icon: const Icon(Icons.videocam_rounded),
                label: Text(live != null ? tr(context, 'Go live', 'Aloita livelähetys') : tr(context, 'Set up a live', 'Valmistele lähetys')),
              ),
              if (live != null)
                OutlinedButton(
                  onPressed: _endingLive ? null : _endCurrentLive,
                  child: Text(tr(context, 'End live', 'Lopeta lähetys')),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _summary() {
    int sum(String k) => _drops.fold(0, (s, d) => s + (asInt(d[k]) ?? 0));
    Widget stat(String label, int value) => Expanded(
          child: Column(children: [
            Text('$value', style: const TextStyle(fontSize: MTextSize.displayS, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            Text(label, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
      child: Row(children: [
        stat(tr(context, 'Live', 'Julkaistu'), _drops.where((d) => d['status'] == 'READY').length),
        stat(tr(context, 'Views', 'Katselut'), sum('viewCount')),
        stat(tr(context, 'Likes', 'Tykkäykset'), sum('likeCount')),
        stat(tr(context, 'Comments', 'Kommentit'), sum('commentCount')),
        stat(tr(context, 'Shares', 'Jaot'), sum('shareCount')),
      ]),
    );
  }

  /// "3 photos", the sound (a library track's title, or "Your sound") and for videos the trimmed length.
  List<Widget> _mediaDetails(Map<String, dynamic> d) {
    final media = d['media'] is Map ? Map<String, dynamic>.from(d['media']) : <String, dynamic>{};
    final isVideo = d['kind'] == 'VIDEO';
    final audio = media['audio'] is Map ? Map<String, dynamic>.from(media['audio']) : null;
    final trim = media['trim'] is Map ? Map<String, dynamic>.from(media['trim']) : null;
    const style = TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary);
    String seconds(num v) {
      final r = (v * 10).round() / 10;
      return r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(1);
    }

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          ]),
        );

    final lines = <Widget>[];
    if (!isVideo) {
      final count = (media['images'] as List?)?.length ?? 1;
      lines.add(line(Icons.photo_library_outlined, tr(context, '$count photo(s)', '$count kuva(a)')));
    }
    if (audio != null) {
      final sound = audio['sound'] is Map ? Map<String, dynamic>.from(audio['sound']) : null;
      var text = sound != null
          ? [sound['title'], if ((sound['artist'] ?? '').toString().isNotEmpty) sound['artist']].join(' · ')
          : tr(context, 'Your sound', 'Oma äänesi');
      if (isVideo && audio['mode'] == 'REPLACE') text += tr(context, ' (video muted)', ' (videon ääni mykistetty)');
      lines.add(line(Icons.music_note_rounded, text));
    }
    final start = trim?['startSec'] as num?;
    final end = trim?['endSec'] as num?;
    if (isVideo && start != null && end != null && end > start) {
      lines.add(line(Icons.content_cut_rounded, tr(context, 'Trimmed: plays ${seconds(end - start)} s', 'Rajattu: toistetaan ${seconds(end - start)} s')));
    }
    return lines;
  }

  Widget _card(Map<String, dynamic> d) {
    final status = d['status'];
    final (label, color) = switch (status) {
      'READY' => (tr(context, 'Live', 'Julkaistu'), AppTheme.primary),
      'PROCESSING' => (tr(context, 'Processing…', 'Käsitellään…'), AppTheme.warning),
      'FAILED' => (tr(context, 'Video could not be processed', 'Videota ei voitu käsitellä'), AppTheme.accent),
      _ => (tr(context, 'Removed', 'Poistettu'), AppTheme.accent),
    };
    final views = asInt(d['viewCount']) ?? 0;
    final completion = views > 0 ? ((asInt(d['completeCount']) ?? 0) * 100 / views).round() : 0;
    final poster = d['media']?['poster'];
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.md), border: Border.all(color: AppTheme.divider)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 110,
              child: poster != null && status == 'READY'
                  ? CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover, placeholder: (_, __) => const MSkeleton(child: MSkeletonBox(height: double.infinity, radius: 0)))
                  : Container(color: AppTheme.primaryLight, child: const Icon(Icons.play_circle_outline, color: AppTheme.primary)),
            ),
          ),
          const SizedBox(width: MSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['product']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((d['caption'] ?? '').toString().isNotEmpty)
                  Text(d['caption'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
                // What the drop is made of: photos (how many), the added sound and a video's trimmed length
                ..._mediaDetails(d),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: MTextSize.caption)),
                if (status == 'REMOVED' && d['removedReason'] != null && d['removedReason'] != 'Deleted by store')
                  Text('${tr(context, 'Reason', 'Syy')}: ${d['removedReason']}', style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  '$views ${tr(context, 'views', 'katselua')} · ${d['likeCount'] ?? 0} ♥ · ${d['shareCount'] ?? 0} ${tr(context, 'shares', 'jakoa')}'
                  '${d['kind'] == 'VIDEO' && views > 0 ? ' · $completion % ${tr(context, 'watched to the end', 'katsoi loppuun')}' : ''}',
                  style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
                ),
                if (status == 'READY')
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => showStoreDropComments(context, d, onCountChanged: (n) {
                      if (mounted) setState(() => d['commentCount'] = n);
                    }),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: Text('${asInt(d['commentCount']) ?? 0} ${tr(context, 'comments', 'kommenttia')}'),
                  ),
              ],
            ),
          ),
          IconButton(tooltip: tr(context, 'Delete drop', 'Poista julkaisu'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(d)),
        ],
      ),
    );
  }
}
