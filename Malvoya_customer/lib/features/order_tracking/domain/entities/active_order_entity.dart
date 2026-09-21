import 'package:equatable/equatable.dart';

enum OrderStatus {
  placed,
  confirmed,
  preparing,
  courierAssigned,
  inTransit,
  delivered,
  cancelled,
}

class ActiveOrderEntity extends Equatable {
  final String id;
  final String storeName;
  final List<String> items;
  final double totalAmount;
  final OrderStatus status;
  final int etaMinutes;
  final String? courierName;
  final double? courierLat;
  final double? courierLng;

  const ActiveOrderEntity({
    required this.id,
    required this.storeName,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.etaMinutes,
    this.courierName,
    this.courierLat,
    this.courierLng,
  });

  @override
  List<Object?> get props => [
        id,
        storeName,
        items,
        totalAmount,
        status,
        etaMinutes,
        courierName,
        courierLat,
        courierLng,
      ];
}
