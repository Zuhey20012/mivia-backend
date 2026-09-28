import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import 'create_drop.dart';

/// Your drops with their real numbers: views, likes, shares and how many watched to the end.
class DropsManager extends StatefulWidget {
  const DropsManager({super.key});

  @override
  State<DropsManager> createState() => DropsManagerState();
}

class DropsManagerState extends State<DropsManager> {
  List<Map<String, dynamic>> _drops = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/drops/mine');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.error;
      if (res.ok) _drops = ((res.data['drops'] as List?) ?? []).map((d) => Map<String, dynamic>.from(d)).toList();
    });
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
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).delete('/drops/${d['id']}');
    if (!mounted) return;
    if (!res.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error!)));
    load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _summary(),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.accent)),
          if (_drops.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                const Icon(Icons.video_camera_back_outlined, size: 56, color: AppTheme.textSecondary),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'Show your items in a short video. Drops appear in the customer app\'s Drops feed with a buy button.',
                      'Esittele tuotteitasi lyhyellä videolla. Julkaisut näkyvät asiakkaiden Drops-syötteessä osta-painikkeen kanssa.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: create, icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'Create your first drop', 'Luo ensimmäinen julkaisu'))),
              ]),
            ),
          for (final d in _drops) _card(d),
        ],
      ),
    );
  }

  Widget _summary() {
    int sum(String k) => _drops.fold(0, (s, d) => s + (asInt(d[k]) ?? 0));
    Widget stat(String label, int value) => Expanded(
          child: Column(children: [
            Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
      child: Row(children: [
        stat(tr(context, 'Live', 'Julkaistu'), _drops.where((d) => d['status'] == 'READY').length),
        stat(tr(context, 'Views', 'Katselut'), sum('viewCount')),
        stat(tr(context, 'Likes', 'Tykkäykset'), sum('likeCount')),
        stat(tr(context, 'Shares', 'Jaot'), sum('shareCount')),
      ]),
    );
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 110,
              child: poster != null && status == 'READY'
                  ? CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover)
                  : Container(color: AppTheme.primaryLight, child: const Icon(Icons.play_circle_outline, color: AppTheme.primary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['product']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((d['caption'] ?? '').toString().isNotEmpty)
                  Text(d['caption'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
                if (status == 'REMOVED' && d['removedReason'] != null && d['removedReason'] != 'Deleted by store')
                  Text('${tr(context, 'Reason', 'Syy')}: ${d['removedReason']}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  '$views ${tr(context, 'views', 'katselua')} · ${d['likeCount'] ?? 0} ♥ · ${d['shareCount'] ?? 0} ${tr(context, 'shares', 'jakoa')}'
                  '${d['kind'] == 'VIDEO' && views > 0 ? ' · $completion % ${tr(context, 'watched to the end', 'katsoi loppuun')}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(d)),
        ],
      ),
    );
  }
}
