import '../entities/active_order_entity.dart';
import '../repositories/order_repository.dart';

class WatchActiveOrderUseCase {
  final OrderRepository repository;
  const WatchActiveOrderUseCase(this.repository);

  Stream<ActiveOrderEntity> call(String orderId) {
    return repository.watchActiveOrder(orderId);
  }
}
