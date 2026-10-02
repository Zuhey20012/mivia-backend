import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/report_reasons.dart';
import '../core/strings.dart';

/// Opens the comments of a drop. [onCountChanged] receives the new visible-comment count.
Future<void> showDropComments(BuildContext context, Map<String, dynamic> drop, {ValueChanged<int>? onCountChanged}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.cardBackground(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DropComments(drop: drop, onCountChanged: onCountChanged),
  );
}

class _DropComments extends StatefulWidget {
  final Map<String, dynamic> drop;
  final ValueChanged<int>? onCountChanged;
  const _DropComments({required this.drop, this.onCountChanged});

  @override
  State<_DropComments> createState() => _DropCommentsState();
}

class _DropCommentsState extends State<_DropComments> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _comments = [];
  int? _nextBefore;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  late int _count = asInt(widget.drop['commentCount']) ?? 0;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));
  String get _base => '/drops/${widget.drop['id']}/comments';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || _nextBefore == null)) return;
    _loadingMore = !reset;
    final res = await _api.get(_base, query: {if (!reset && _nextBefore != null) 'before': '$_nextBefore'});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (!res.ok) {
        if (reset) _error = res.error;
        return;
      }
      if (reset) _comments.clear();
      _comments.addAll(((res.data['comments'] as List?) ?? []).map((c) => Map<String, dynamic>.from(c)));
      _nextBefore = asInt(res.data['nextBefore']);
    });
  }

  void _setCount(int n) {
    _count = n < 0 ? 0 : n;
    widget.onCountChanged?.call(_count);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await _api.post(_base, {'body': text});
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (res.ok) {
        _comments.insert(0, Map<String, dynamic>.from(res.data['comment']));
        _input.clear();
        _setCount(_count + 1);
      }
    });
    if (res.ok) {
      HapticFeedback.lightImpact();
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _snack(res.error!);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final res = await _api.delete('$_base/${c['id']}');
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _comments.remove(c);
        _setCount(_count - 1);
      });
    } else {
      _snack(res.error!);
    }
  }

  Future<void> _report(Map<String, dynamic> c) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(tr(ctx, 'Report this comment', 'Ilmoita kommentista'), style: const TextStyle(fontWeight: FontWeight.w700))),
          for (final e in reportReasons.entries)
            ListTile(title: Text(isFinnish(ctx) ? e.value[1] : e.value[0]), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (reason == null || !mounted) return;
    final res = await _api.post('$_base/${c['id']}/report', {'reason': reason});
    if (mounted) _snack(res.ok ? tr(context, 'Thanks — we will review it.', 'Kiitos — tarkistamme sen.') : res.error!);
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  String _ago(dynamic iso) {
    final t = DateTime.tryParse('$iso');
    if (t == null) return '';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return tr(context, 'now', 'nyt');
    if (d.inHours < 1) return '${d.inMinutes} min';
    if (d.inDays < 1) return '${d.inHours} h';
    if (d.inDays < 7) return isFinnish(context) ? '${d.inDays} pv' : '${d.inDays} d';
    return '${t.day}.${t.month}.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: textSecondary.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                _count == 1 ? tr(context, '1 comment', '1 kommentti') : tr(context, '$_count comments', '$_count kommenttia'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: textSecondary)))
                      : _comments.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(tr(context, 'No comments yet. Ask the store about sizes, fabric or fit.', 'Ei vielä kommentteja. Kysy kaupalta koosta, materiaalista tai istuvuudesta.'),
                                    textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _comments.length,
                              itemBuilder: (_, i) => _tile(_comments[i], auth, textPrimary, textSecondary),
                            ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: auth.isAuthenticated
                    ? Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            maxLength: 300,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: tr(context, 'Add a comment…', 'Lisää kommentti…'),
                              counterText: '',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr(context, 'Send', 'Lähetä'),
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_rounded, color: AppTheme.primary),
                        ),
                      ])
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(tr(context, 'Sign in to comment', 'Kirjaudu sisään kommentoidaksesi'), style: TextStyle(color: textSecondary)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c, AuthService auth, Color textPrimary, Color textSecondary) {
    final byStore = c['byStore'] == true;
    final canDelete = c['canDelete'] == true;
    final canReport = auth.isAuthenticated && c['mine'] != true;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: byStore ? AppTheme.primary : AppTheme.primaryLight,
        child: byStore
            ? const Icon(Icons.storefront_rounded, color: Colors.white, size: 20)
            : Text('${c['author'] ?? '?'}'.characters.first.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800)),
      ),
      title: Row(children: [
        Flexible(child: Text('${c['author'] ?? ''}', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary))),
        if (byStore)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(6)),
            child: Text(tr(context, 'Store', 'Kauppa'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(width: 6),
        Text(_ago(c['createdAt']), style: TextStyle(fontSize: 12, color: textSecondary)),
      ]),
      subtitle: Text('${c['body'] ?? ''}', style: TextStyle(color: textPrimary, fontSize: 14, height: 1.3)),
      trailing: canDelete || canReport
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: textSecondary, size: 20),
              onSelected: (v) => v == 'delete' ? _delete(c) : _report(c),
              itemBuilder: (_) => [
                if (canDelete) PopupMenuItem(value: 'delete', child: Text(tr(context, 'Delete', 'Poista'))),
                if (canReport) PopupMenuItem(value: 'report', child: Text(tr(context, 'Report', 'Ilmoita'))),
              ],
            )
          : null,
    );
  }
}
