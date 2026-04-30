import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config/constants.dart';
import 'auth_service.dart';

class AdminStats {
  final double totalSales;
  final int activeOrders;
  final int activeCouriers;
  final int totalStores;

  AdminStats({
    required this.totalSales,
    required this.activeOrders,
    required this.activeCouriers,
    required this.totalStores,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalSales: (json['totalSales'] ?? 0).toDouble(),
      activeOrders: json['activeOrders'] ?? 0,
      activeCouriers: json['activeCouriers'] ?? 0,
      totalStores: json['totalStores'] ?? 0,
    );
  }
}

class AdminService extends ChangeNotifier {
  final AuthService _auth;

  AdminService(this._auth);

  Future<AdminStats?> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiBase}/admin/stats'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return AdminStats.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint("Fetch Admin Stats Error: $e");
      return null;
    }
  }

  Future<List<dynamic>> getPendingVendors() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiBase}/admin/vendors?status=PENDING'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint("Fetch Pending Vendors Error: $e");
      return [];
    }
  }

  Future<bool> approveVendor(int id) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConstants.apiBase}/admin/vendors/$id/approve'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Approve Vendor Error: $e");
      return false;
    }
  }
}
