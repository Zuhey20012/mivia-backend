import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../config/constants.dart';
import '../../domain/entities/active_order_entity.dart';
import '../../domain/repositories/order_repository.dart';

class OrderRepositoryImpl implements OrderRepository {
  final String? accessToken;

  OrderRepositoryImpl({this.accessToken});

  @override
  Stream<ActiveOrderEntity> watchActiveOrder(String orderId) async* {
    // Initial fetch
    final entity = await _fetchOrder(orderId);
    if (entity != null) yield entity;

    // Periodic stream polling for live updates
    while (true) {
      await Future.delayed(const Duration(seconds: 4));
      final update = await _fetchOrder(orderId);
      if (update != null) {
        yield update;
        if (update.status == OrderStatus.delivered || update.status == OrderStatus.cancelled) {
          break;
        }
      }
    }
  }

  Future<ActiveOrderEntity?> _fetchOrder(String orderId) async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/orders/$orderId'),
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final order = data['order'] ?? data;
        final rawStatus = (order['status'] ?? 'PENDING').toString().toUpperCase();

        OrderStatus status = OrderStatus.placed;
        if (rawStatus == 'CONFIRMED') status = OrderStatus.confirmed;
        if (rawStatus == 'PROCESSING') status = OrderStatus.preparing;
        if (rawStatus == 'SHIPPED') status = OrderStatus.inTransit;
        if (rawStatus == 'DELIVERED') status = OrderStatus.delivered;
        if (rawStatus == 'CANCELLED') status = OrderStatus.cancelled;

        return ActiveOrderEntity(
          id: order['id']?.toString() ?? orderId,
          storeName: order['store']?['name'] ?? 'Local Nordic Boutique',
          items: (order['items'] as List?)?.map((i) => i['name']?.toString() ?? 'Garment').toList() ?? ['Garment Piece'],
          totalAmount: (order['total'] as num?)?.toDouble() ?? 48.50,
          status: status,
          etaMinutes: (order['etaMinutes'] as num?)?.toInt() ?? 18,
          courierName: order['courier']?['name'] ?? 'Boutique Courier',
          courierLat: (order['courierLat'] as num?)?.toDouble(),
          courierLng: (order['courierLng'] as num?)?.toDouble(),
        );
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> cancelOrder(String orderId, String reason) async {
    try {
      await http.post(
        Uri.parse('${AppConstants.apiBase}/orders/$orderId/cancel'),
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reason': reason}),
      );
    } catch (_) {}
  }
}
