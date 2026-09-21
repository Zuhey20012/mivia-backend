import 'package:flutter/material.dart';
import '../screens/map_tracker.dart';

/// Master Operational Portal (MasterOperationalPortal):
/// Integrates the high-frequency sub-second GPS map tracking,
/// 5-stage state progression (PLACED, PREPARING, COURIER_ASSIGNED, IN_TRANSIT, DELIVERED),
/// DraggableScrollableSheet with snap points [0.18, 0.32, 0.88] and 50% boundary velocity haptics,
/// plus the in-transit masked communications bridge (zero-PII VoIP calling & encrypted chat).
class MasterOperationalPortal extends StatelessWidget {
  final String orderId;
  final String merchantName;
  final String courierName;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? deliveryAddress;

  const MasterOperationalPortal({
    super.key,
    this.orderId = 'Order Tracking',
    this.merchantName = 'Partner Boutique',
    this.courierName = 'Verified Express Courier',
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryAddress,
  });

  @override
  Widget build(BuildContext context) {
    return MapTrackerScreen(
      orderId: orderId,
      merchantName: merchantName,
      courierName: courierName,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
      deliveryAddress: deliveryAddress,
    );
  }
}
