import 'package:flutter/material.dart';

import '../../shared/models/transit_models.dart';
import '../../shared/widgets/live_route_map.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخريطة')),
      body: Stack(
        children: [
          LiveRouteMap(
            stops: sampleStops,
            vehicles: sampleVehicles,
            pickupStop: sampleStops[1],
            selectedVehicle: sampleVehicles[0],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus_filled,
                        color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text('${sampleRoute.nameAr}\nموقعك قرب الصالحية',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                    const Text('الأقرب: ٦ د'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
