import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/active_order_entity.dart';
import '../../domain/usecases/watch_active_order_usecase.dart';
import '../../domain/usecases/cancel_order_usecase.dart';

// Sealed Order Events
abstract class ActiveOrderEvent extends Equatable {
  const ActiveOrderEvent();
  @override
  List<Object?> get props => [];
}

class StartOrderStream extends ActiveOrderEvent {
  final String orderId;
  const StartOrderStream(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

class _OrderUpdatedInternal extends ActiveOrderEvent {
  final ActiveOrderEntity order;
  const _OrderUpdatedInternal(this.order);
  @override
  List<Object?> get props => [order];
}

class CancelActiveOrder extends ActiveOrderEvent {
  final String reason;
  const CancelActiveOrder(this.reason);
  @override
  List<Object?> get props => [reason];
}

// Sealed Order States
abstract class ActiveOrderState extends Equatable {
  const ActiveOrderState();
  @override
  List<Object?> get props => [];
}

class ActiveOrderInitial extends ActiveOrderState {}

class ActiveOrderLoading extends ActiveOrderState {}

class OrderProgressState extends ActiveOrderState {
  final ActiveOrderEntity order;
  final double progressPercent; // 0.15, 0.35, 0.55, 0.70, 0.88, 1.0
  final String stepDescription;

  const OrderProgressState({
    required this.order,
    required this.progressPercent,
    required this.stepDescription,
  });

  @override
  List<Object?> get props => [order, progressPercent, stepDescription];
}

class ActiveOrderDelivered extends ActiveOrderState {
  final ActiveOrderEntity order;
  const ActiveOrderDelivered(this.order);
  @override
  List<Object?> get props => [order];
}

class ActiveOrderError extends ActiveOrderState {
  final String message;
  const ActiveOrderError(this.message);
  @override
  List<Object?> get props => [message];
}

// Wolt/Uber Active-Order State Machine BLoC Implementation
class ActiveOrderBloc extends Bloc<ActiveOrderEvent, ActiveOrderState> {
  final WatchActiveOrderUseCase _watchOrder;
  final CancelOrderUseCase _cancelOrder;
  StreamSubscription<ActiveOrderEntity>? _orderSubscription;

  ActiveOrderBloc({
    required WatchActiveOrderUseCase watchOrder,
    required CancelOrderUseCase cancelOrder,
  })  : _watchOrder = watchOrder,
        _cancelOrder = cancelOrder,
        super(ActiveOrderInitial()) {
    on<StartOrderStream>(_onStartOrderStream);
    on<_OrderUpdatedInternal>(_onOrderUpdated);
    on<CancelActiveOrder>(_onCancelActiveOrder);
  }

  Future<void> _onStartOrderStream(
    StartOrderStream event,
    Emitter<ActiveOrderState> emit,
  ) async {
    emit(ActiveOrderLoading());
    await _orderSubscription?.cancel();
    _orderSubscription = _watchOrder(event.orderId).listen(
      (order) => add(_OrderUpdatedInternal(order)),
      onError: (err) => emit(ActiveOrderError(err.toString())),
    );
  }

  void _onOrderUpdated(
    _OrderUpdatedInternal event,
    Emitter<ActiveOrderState> emit,
  ) {
    final order = event.order;
    switch (order.status) {
      case OrderStatus.placed:
        emit(OrderProgressState(
          order: order,
          progressPercent: 0.15,
          stepDescription: 'Waiting for atelier confirmation',
        ));
        break;
      case OrderStatus.confirmed:
        emit(OrderProgressState(
          order: order,
          progressPercent: 0.35,
          stepDescription: 'Atelier confirmed your order',
        ));
        break;
      case OrderStatus.preparing:
        emit(OrderProgressState(
          order: order,
          progressPercent: 0.55,
          stepDescription: 'Atelier is preparing garments on cedar hangers',
        ));
        break;
      case OrderStatus.courierAssigned:
        emit(OrderProgressState(
          order: order,
          progressPercent: 0.70,
          stepDescription: 'Courier assigned & heading to boutique',
        ));
        break;
      case OrderStatus.inTransit:
        emit(OrderProgressState(
          order: order,
          progressPercent: 0.88,
          stepDescription: 'Courier is in transit to your doorstep',
        ));
        break;
      case OrderStatus.delivered:
        emit(ActiveOrderDelivered(order));
        break;
      case OrderStatus.cancelled:
        emit(const ActiveOrderError('Order was cancelled'));
        break;
    }
  }

  Future<void> _onCancelActiveOrder(
    CancelActiveOrder event,
    Emitter<ActiveOrderState> emit,
  ) async {
    final currentState = state;
    if (currentState is OrderProgressState) {
      await _cancelOrder(currentState.order.id, event.reason);
    }
  }

  @override
  Future<void> close() {
    _orderSubscription?.cancel();
    return super.close();
  }
}
