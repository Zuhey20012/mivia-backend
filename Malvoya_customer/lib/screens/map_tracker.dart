import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapTrackerScreen extends StatefulWidget {
  const MapTrackerScreen({super.key});

  @override
  State<MapTrackerScreen> createState() => _MapTrackerScreenState();
}

class _MapTrackerScreenState extends State<MapTrackerScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  final LatLng _courierPos = LatLng(60.1699, 24.9384); // Helsinki
  final LatLng _homePos = LatLng(60.1750, 24.9420); // Destination

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(60.1720, 24.9400),
              zoom: 14.5,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.malvoya.customer',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [_courierPos, LatLng(60.1710, 24.9390), _homePos],
                    strokeWidth: 4.0,
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _homePos,
                    builder: (ctx) => const Icon(Icons.home, color: Colors.red, size: 40),
                  ),
                  Marker(
                    point: _courierPos,
                    builder: (ctx) => Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: const Icon(Icons.delivery_dining, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  const Text('Arriving in 15 mins', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Courier Mikael K. is on the way', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      CircleAvatar(radius: 24, backgroundColor: Colors.grey.shade200, child: const Icon(Icons.person, color: Colors.grey)),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mikael K.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Row(children: [Icon(Icons.star, size: 16, color: Colors.amber), Text(' 4.9')])
                          ],
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () {}),
                      ),
                      const SizedBox(width: 12),
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: IconButton(icon: const Icon(Icons.message, color: Colors.blue), onPressed: () {}),
                      )
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
