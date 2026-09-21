import '../repositories/order_repository.dart';

class CancelOrderUseCase {
  final OrderRepository repository;
  const CancelOrderUseCase(this.repository);

  Future<void> call(String orderId, String reason) {
    return repository.cancelOrder(orderId, reason);
  }
}
