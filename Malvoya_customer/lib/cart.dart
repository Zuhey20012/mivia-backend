import 'package:flutter/material.dart';
import 'models.dart';

class CartService extends ChangeNotifier {
  final List<CartItem> _items = [];
  int? _storeId;
  String? _storeName;

  List<CartItem> get items => List.unmodifiable(_items);
  int? get storeId => _storeId;
  String? get storeName => _storeName;
  int get itemCount => _items.fold(0, (s, i) => s + i.quantity);
  double get total => _items.fold(0.0, (s, i) => s + i.price * i.quantity);

  bool canAddDirectly(int? incomingStoreId) {
    if (_items.isEmpty || _storeId == null || incomingStoreId == null) return true;
    return _storeId == incomingStoreId;
  }

  void add(CartItem item, {bool forceClear = false}) {
    if (forceClear) {
      _items.clear();
      _storeId = null;
      _storeName = null;
    }
    _storeId ??= item.storeId;
    _storeName ??= item.storeName;

    final existing = _items.indexWhere((it) =>
        it.productId == item.productId && it.variantId == item.variantId);
    if (existing >= 0) {
      _items[existing].quantity += item.quantity;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void remove(CartItem item) {
    _items.removeWhere((it) =>
        it.productId == item.productId && it.variantId == item.variantId);
    if (_items.isEmpty) {
      _storeId = null;
      _storeName = null;
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _storeId = null;
    _storeName = null;
    notifyListeners();
  }

  void changeQuantity(CartItem item, int qty) {
    final idx = _items.indexWhere((it) =>
        it.productId == item.productId && it.variantId == item.variantId);
    if (idx >= 0) {
      if (qty <= 0) {
        _items.removeAt(idx);
      } else {
        _items[idx].quantity = qty;
      }
      if (_items.isEmpty) {
        _storeId = null;
        _storeName = null;
      }
      notifyListeners();
    }
  }
}
