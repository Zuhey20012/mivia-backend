import '../entities/active_order_entity.dart';

abstract class OrderRepository {
  Stream<ActiveOrderEntity> watchActiveOrder(String orderId);
  Future<void> cancelOrder(String orderId, String reason);
}
