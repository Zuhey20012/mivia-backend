import 'package:flutter/material.dart';
import 'models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

class CartService extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  double get total => _items.fold(0.0, (s, i) => s + i.price * i.quantity);

  void add(CartItem item) {
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
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void changeQuantity(CartItem item, int qty) {
    final idx = _items.indexWhere((it) =>
        it.productId == item.productId && it.variantId == item.variantId);
    if (idx >= 0) {
      _items[idx].quantity = qty;
      if (qty <= 0) _items.removeAt(idx);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> checkout(int userId, String authToken) async {
    final body = {
      'userId': userId,
      'items': _items.map((i) => i.toOrderItem()).toList(),
      'total': total,
    };
    final res = await http.post(
      Uri.parse('${AppConstants.apiBase}/orders'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode == 201 || res.statusCode == 200) {
      clear();
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception('Checkout failed: ${res.statusCode} ${res.body}');
    }
  }
}
