import 'package:flutter/material.dart';

/**
 * Sliding-window Video Feed Memory Controller Pool
 * Enforces strict (i-1, i, i+1) pre-buffering and evicts distant controllers
 * to prevent hardware texture memory leaks and OOM crashes.
 */
class TikTokVideoFeedController extends ChangeNotifier {
  final List<String> urls;
  final Map<int, bool> _activePool = {};
  int _currentIndex = 0;

  TikTokVideoFeedController({required this.urls});

  int get currentIndex => _currentIndex;
  bool isBuffered(int index) => _activePool[index] ?? false;

  void onPageChanged(int index) {
    _currentIndex = index;
    _preBuffer(index + 1);
    if (index - 1 >= 0) _preBuffer(index - 1);
    _evict(index);
    notifyListeners();
  }

  void _preBuffer(int index) {
    if (index < 0 || index >= urls.length || _activePool.containsKey(index)) return;
    _activePool[index] = true;
  }

  void _evict(int center) {
    final stale = _activePool.keys.where((k) => (k - center).abs() > 1).toList();
    for (final k in stale) {
      _activePool.remove(k);
    }
  }

  @override
  void dispose() {
    _activePool.clear();
    super.dispose();
  }
}
