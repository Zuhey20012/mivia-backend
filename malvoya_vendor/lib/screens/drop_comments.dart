import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';

/// Comments on one of the store's drops: answer as the store, or delete comments that do not belong there.
Future<void> showStoreDropComments(BuildContext context, Map<String, dynamic> drop, {ValueChanged<int>? onCountChanged}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _StoreDropComments(drop: drop, onCountChanged: onCountChanged),
  );
}

class _StoreDropComments extends StatefulWidget {
  final Map<String, dynamic> drop;
  final ValueChanged<int>? onCountChanged;
  const _StoreDropComments({required this.drop, this.onCountChanged});

  @override
  State<_StoreDropComments> createState() => _StoreDropCommentsState();
}

class _StoreDropCommentsState extends State<_StoreDropComments> {
  final _input = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];
  int? _nextBefore;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  late int _count = asInt(widget.drop['commentCount']) ?? 0;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));
  String get _base => '/drops/${widget.drop['id']}/comments';

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final res = await _api.get(_base, query: {if (!reset && _nextBefore != null) 'before': '$_nextBefore'});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!res.ok) {
        _error = res.error;
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

  Future<void> _reply() async {
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
    if (!res.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error!)));
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Delete this comment?', 'Poistetaanko kommentti?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'Delete', 'Poista'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.delete('$_base/${c['id']}');
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _comments.remove(c);
        _setCount(_count - 1);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _count == 1 ? tr(context, '1 comment', '1 kommentti') : tr(context, '$_count comments', '$_count kommenttia'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _comments.isEmpty
                        ? Center(child: Text(tr(context, 'No comments yet.', 'Ei vielä kommentteja.'), style: const TextStyle(color: AppTheme.textSecondary)))
                        : ListView(children: [
                            for (final c in _comments)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: c['byStore'] == true ? AppTheme.primary : AppTheme.primaryLight,
                                  child: Icon(c['byStore'] == true ? Icons.storefront_rounded : Icons.person_outline_rounded,
                                      color: c['byStore'] == true ? Colors.white : AppTheme.primary, size: 20),
                                ),
                                title: Text('${c['author'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                subtitle: Text('${c['body'] ?? ''}', style: const TextStyle(color: AppTheme.textPrimary)),
                                trailing: c['canDelete'] == true
                                    ? IconButton(tooltip: tr(context, 'Delete', 'Poista'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(c))
                                    : null,
                              ),
                            if (_nextBefore != null)
                              TextButton(onPressed: _load, child: Text(tr(context, 'Show older comments', 'Näytä vanhemmat'))),
                          ]),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 300,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: tr(context, 'Reply as your store…', 'Vastaa kauppana…'),
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Send', 'Lähetä'),
                  onPressed: _sending ? null : _reply,
                  icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
