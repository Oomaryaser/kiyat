import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/transit_models.dart';

class LiveRouteMap extends StatefulWidget {
  const LiveRouteMap({
    super.key,
    required this.stops,
    required this.vehicles,
    required this.pickupStop,
    required this.selectedVehicle,
    this.compact = false,
  });

  final List<TransitStop> stops;
  final List<VehicleArrivalEstimate> vehicles;
  final TransitStop? pickupStop;
  final VehicleArrivalEstimate? selectedVehicle;
  final bool compact;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> {
  static const _directionsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  GoogleMapController? _controller;
  List<LatLng> _roadRoute = const [];

  @override
  void initState() {
    super.initState();
    _loadGoogleRoute();
  }

  @override
  void didUpdateWidget(covariant LiveRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stops != widget.stops ||
        oldWidget.pickupStop != widget.pickupStop) {
      _loadGoogleRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.pickupStop == null
        ? LatLng(widget.stops[1].lat, widget.stops[1].lng)
        : LatLng(widget.pickupStop!.lat, widget.pickupStop!.lng);
    final routePoints = _roadRoute.isEmpty
        ? widget.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList()
        : _roadRoute;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.compact ? 8 : 0),
      child: GoogleMap(
        initialCameraPosition:
            CameraPosition(target: center, zoom: widget.compact ? 14.6 : 13.4),
        onMapCreated: (controller) {
          _controller = controller;
          _fitCamera(routePoints);
        },
        mapType: MapType.normal,
        compassEnabled: !widget.compact,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        markers: _markers,
        polylines: {
          Polyline(
            polylineId: const PolylineId('kiyat_route_shadow'),
            points: routePoints,
            color: Colors.white,
            width: widget.compact ? 8 : 10,
            zIndex: 1,
          ),
          Polyline(
            polylineId: const PolylineId('kiyat_route'),
            points: routePoints,
            color: const Color(0xFF1B5E8B),
            width: widget.compact ? 5 : 6,
            zIndex: 2,
          ),
        },
      ),
    );
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};

    for (final stop in widget.stops) {
      markers.add(
        Marker(
          markerId: MarkerId('landmark_${stop.id}'),
          position: LatLng(stop.lat, stop.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(stop.isMajor
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: stop.nameAr, snippet: stop.landmarkAr),
        ),
      );
    }

    if (widget.pickupStop != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_location'),
          position: LatLng(widget.pickupStop!.lat, widget.pickupStop!.lng),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
              title: 'موقعك الحالي', snippet: 'نقطة الصعود على مسار الخط'),
          zIndexInt: 10,
        ),
      );
    }

    for (final vehicle in widget.vehicles) {
      final isSelected =
          widget.selectedVehicle?.vehicleLabel == vehicle.vehicleLabel;
      markers.add(
        Marker(
          markerId: MarkerId('vehicle_${vehicle.vehicleLabel}'),
          position: LatLng(vehicle.lat, vehicle.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isSelected
                ? BitmapDescriptor.hueOrange
                : vehicle.hasPassedPickup
                    ? BitmapDescriptor.hueYellow
                    : BitmapDescriptor.hueBlue,
          ),
          infoWindow: InfoWindow(
            title: isSelected
                ? 'الأقرب • ${vehicle.etaMinutes} د'
                : vehicle.vehicleLabel,
            snippet: vehicle.hasPassedPickup
                ? 'عدّت مكان صعودك'
                : 'قرب ${vehicle.nearStopName}',
          ),
          zIndexInt: isSelected ? 12 : 8,
        ),
      );
    }

    return markers;
  }

  Future<void> _loadGoogleRoute() async {
    final fallback =
        widget.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList();
    if (_directionsApiKey.isEmpty || widget.stops.length < 2) {
      setState(() => _roadRoute = fallback);
      return;
    }

    final origin = widget.stops.first;
    final destination = widget.stops.last;
    final waypoints = widget.stops.length > 2
        ? widget.stops
            .sublist(1, widget.stops.length - 1)
            .map((stop) => '${stop.lat},${stop.lng}')
            .join('|')
        : null;
    final query = {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
      'mode': 'driving',
      'key': _directionsApiKey,
      if (waypoints != null) 'waypoints': waypoints,
    };
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/directions/json', query);

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        setState(() => _roadRoute = fallback);
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      final encoded =
          routes?.firstOrNull?['overview_polyline']?['points'] as String?;
      if (encoded == null || encoded.isEmpty) {
        setState(() => _roadRoute = fallback);
        return;
      }

      final decoded = _decodePolyline(encoded);
      setState(() => _roadRoute = decoded.isEmpty ? fallback : decoded);
      await _fitCamera(decoded.isEmpty ? fallback : decoded);
    } catch (_) {
      setState(() => _roadRoute = fallback);
    }
  }

  Future<void> _fitCamera(List<LatLng> routePoints) async {
    final controller = _controller;
    if (controller == null || routePoints.length < 2) return;

    final points = [
      ...routePoints,
      if (widget.pickupStop != null)
        LatLng(widget.pickupStop!.lat, widget.pickupStop!.lng),
      ...widget.vehicles.map((vehicle) => LatLng(vehicle.lat, vehicle.lng)),
    ];
    await controller.animateCamera(CameraUpdate.newLatLngBounds(
        _boundsFor(points), widget.compact ? 24 : 56));
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }

    return LatLngBounds(
        southwest: LatLng(south, west), northeast: LatLng(north, east));
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
}
