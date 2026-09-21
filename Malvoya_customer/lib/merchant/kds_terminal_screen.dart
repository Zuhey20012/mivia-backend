import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/**
 * Merchant In-Store Tablet KDS Screen (Always-Awake Grid & Pick Tickets)
 * Real-time order grid for high-end boutique apparel preparation and concierge fitting packing.
 * 100% Luxury Apparel Fashion — Zero restaurants.
 */
class MerchantKDSScreen extends StatefulWidget {
  final String boutiqueId;
  const MerchantKDSScreen({super.key, required this.boutiqueId});

  @override
  State<MerchantKDSScreen> createState() => _MerchantKDSScreenState();
}

class _MerchantKDSScreenState extends State<MerchantKDSScreen> {
  final List<Map<String, dynamic>> _orders = [];

  void _updateStatus(int index, String newStatus) {
    HapticFeedback.mediumImpact();
    setState(() {
      _orders[index]['status'] = newStatus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        elevation: 0,
        title: Text(
          "Boutique KDS Terminal • Store #${widget.boutiqueId}",
          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.pause_circle_outline, color: Colors.amber),
            tooltip: 'Pause incoming queue',
            onPressed: () {},
          )
        ],
      ),
      body: _orders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.cyan.shade300),
                  const SizedBox(height: 12),
                  const Text(
                    "All Boutique Orders Prepared",
                    style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.95,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _orders.length,
              itemBuilder: (context, idx) {
                final o = _orders[idx];
                final id = o['id'] as String;
                final status = o['status'] as String;
                final isPlaced = status == 'PLACED';
                final isPreparing = status == 'PREPARING';

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isPlaced
                          ? const Color(0xFF00C2E8)
                          : isPreparing
                              ? Colors.amber
                              : const Color(0xFF10B981),
                      width: 1.8,
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "#$id",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isPlaced ? const Color(0xFF00C2E8) : isPreparing ? Colors.amber : const Color(0xFF10B981)).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: isPlaced ? const Color(0xFF38BDF8) : isPreparing ? Colors.amberAccent : const Color(0xFF34D399),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (o['brand'] ?? '').toUpperCase(),
                        style: const TextStyle(color: Color(0xFF00C2E8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        o['title'] ?? 'Luxury Apparel Item',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "Sizes to Pack: ${(o['trySizes'] as List?)?.join(' & ') ?? 'M'}",
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      if (isPlaced)
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C2E8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _updateStatus(idx, 'PREPARING'),
                            child: const Text(
                              "Accept & Pick Ticket",
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        )
                      else if (isPreparing)
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _updateStatus(idx, 'READY'),
                            child: const Text(
                              "Mark Packed & Ready",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              "✓ Awaiting Courier Pickup",
                              style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
