import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    this.extraRouteLines = const [],
  });

  final List<TransitStop> stops;
  final List<VehicleArrivalEstimate> vehicles;
  final TransitStop? pickupStop;
  final VehicleArrivalEstimate? selectedVehicle;
  final bool compact;
  final List<List<TransitStop>> extraRouteLines;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap>
    with SingleTickerProviderStateMixin {
  static const _directionsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const _cleanMapStyle = '''
[
  {
    "featureType": "poi",
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "poi.business",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  }
]
''';

  GoogleMapController? _controller;
  List<LatLng> _roadRoute = const [];
  AnimationController? _pulseController;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _majorStopIcon;
  BitmapDescriptor? _minorStopIcon;
  BitmapDescriptor? _selectedVehicleIcon;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _passedVehicleIcon;

  @override
  void initState() {
    super.initState();
    _ensurePulseController();
    _loadMarkerIcons();
    _loadGoogleRoute();
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
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
    final pulseController = _ensurePulseController();

    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 8 : 0),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
              target: center, zoom: widget.compact ? 14.6 : 13.4),
          onMapCreated: (controller) {
            _controller = controller;
            _fitCamera(routePoints);
          },
          style: _cleanMapStyle,
          mapType: MapType.normal,
          compassEnabled: !widget.compact,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          mapToolbarEnabled: false,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              EagerGestureRecognizer.new,
            ),
          },
          markers: _markers,
          circles: _pulseCircles,
          polylines: {
            for (var i = 0; i < widget.extraRouteLines.length; i += 1)
              if (widget.extraRouteLines[i].length > 1)
                Polyline(
                  polylineId: PolylineId('other_route_$i'),
                  points: widget.extraRouteLines[i]
                      .map((stop) => LatLng(stop.lat, stop.lng))
                      .toList(),
                  color: const Color(0xFF455A64).withValues(alpha: 0.32),
                  width: widget.compact ? 3 : 4,
                  zIndex: 0,
                ),
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
      ),
    );
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final majorStopIcon = _majorStopIcon;
    final minorStopIcon = _minorStopIcon;
    final pickupIcon = _pickupIcon;
    final selectedVehicleIcon = _selectedVehicleIcon;
    final vehicleIcon = _vehicleIcon;
    final passedVehicleIcon = _passedVehicleIcon;

    for (final stop in widget.stops) {
      final icon = stop.isMajor ? majorStopIcon : minorStopIcon;
      if (icon == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('landmark_${stop.id}'),
          position: LatLng(stop.lat, stop.lng),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: stop.nameAr, snippet: stop.landmarkAr),
          zIndexInt: 3,
        ),
      );
    }

    if (widget.pickupStop != null && pickupIcon != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_location'),
          position: LatLng(widget.pickupStop!.lat, widget.pickupStop!.lng),
          icon: pickupIcon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(
              title: 'موقعك الحالي', snippet: 'نقطة الصعود على مسار الخط'),
          zIndexInt: 10,
        ),
      );
    }

    for (final vehicle in widget.vehicles) {
      final isSelected =
          widget.selectedVehicle?.vehicleLabel == vehicle.vehicleLabel;
      final icon = isSelected
          ? selectedVehicleIcon
          : vehicle.hasPassedPickup
              ? passedVehicleIcon
              : vehicleIcon;
      if (icon == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('vehicle_${vehicle.vehicleLabel}'),
          position: LatLng(vehicle.lat, vehicle.lng),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
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

  Set<Circle> get _pulseCircles {
    final selected = widget.selectedVehicle;
    if (selected == null) return const {};

    final progress = _pulseController?.value ?? 0;
    final radius = 80 + (progress * 150);
    final opacity = 0.42 * (1 - progress);
    return {
      Circle(
        circleId: const CircleId('selected_vehicle_pulse'),
        center: LatLng(selected.lat, selected.lng),
        radius: radius,
        fillColor: const Color(0xFFF5A623).withValues(alpha: opacity),
        strokeColor: const Color(0xFFF5A623).withValues(alpha: opacity + 0.08),
        strokeWidth: 2,
        zIndex: 4,
      ),
      Circle(
        circleId: const CircleId('selected_vehicle_inner_pulse'),
        center: LatLng(selected.lat, selected.lng),
        radius: 38 + (progress * 46),
        fillColor: const Color(0xFFF5A623).withValues(alpha: 0.2),
        strokeColor: const Color(0xFFF5A623).withValues(alpha: 0.55),
        strokeWidth: 3,
        zIndex: 5,
      ),
    };
  }

  Future<void> _loadMarkerIcons() async {
    final icons = await Future.wait([
      _buildPickupIcon(),
      _buildStopDotIcon(const Color(0xFF1B5E8B), 28),
      _buildStopDotIcon(const Color(0xFF7BA9C6), 22),
      _buildVehicleIcon(
        bodyColor: const Color(0xFFF5A623),
        roofColor: const Color(0xFF1B5E8B),
        label: 'كية',
      ),
      _buildVehicleIcon(
        bodyColor: const Color(0xFF1B5E8B),
        roofColor: const Color(0xFF0E3148),
        label: 'كية',
      ),
      _buildVehicleIcon(
        bodyColor: const Color(0xFFB7BDC5),
        roofColor: const Color(0xFF7C8793),
        label: 'عدت',
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _pickupIcon = icons[0];
      _majorStopIcon = icons[1];
      _minorStopIcon = icons[2];
      _selectedVehicleIcon = icons[3];
      _vehicleIcon = icons[4];
      _passedVehicleIcon = icons[5];
    });
  }

  AnimationController _ensurePulseController() {
    return _pulseController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
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

  Future<BitmapDescriptor> _buildPickupIcon() async {
    const size = 84.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    canvas.drawCircle(
      center,
      30,
      Paint()..color = const Color(0xFF1B5E8B).withValues(alpha: 0.16),
    );
    canvas.drawCircle(center, 18, Paint()..color = Colors.white);
    canvas.drawCircle(center, 12, Paint()..color = const Color(0xFF1B5E8B));
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);

    final bytes = await _pictureToBytes(recorder, size.toInt(), size.toInt());
    return BitmapDescriptor.bytes(bytes, width: 42, height: 42);
  }

  Future<BitmapDescriptor> _buildStopDotIcon(Color color, double size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    canvas.drawCircle(
      center,
      size * 0.42,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      size * 0.31,
      Paint()..color = color,
    );
    canvas.drawCircle(
      center,
      size * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    final bytes = await _pictureToBytes(recorder, size.toInt(), size.toInt());
    return BitmapDescriptor.bytes(bytes, width: size / 2, height: size / 2);
  }

  Future<BitmapDescriptor> _buildVehicleIcon({
    required Color bodyColor,
    required Color roofColor,
    required String label,
  }) async {
    const width = 112.0;
    const height = 82.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 22, 76, 42),
        const Radius.circular(14),
      ),
      shadowPaint,
    );

    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(16, 18, 80, 44),
      const Radius.circular(14),
    );
    canvas.drawRRect(body, Paint()..color = bodyColor);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white,
    );

    final roofPath = Path()
      ..moveTo(32, 18)
      ..lineTo(48, 6)
      ..lineTo(72, 6)
      ..lineTo(88, 18)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roofColor);

    final windowPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(34, 24, 18, 14),
        const Radius.circular(4),
      ),
      windowPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 24, 18, 14),
        const Radius.circular(4),
      ),
      windowPaint,
    );

    canvas.drawCircle(const Offset(34, 62), 8, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(78, 62), 8, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(34, 62), 4, Paint()..color = roofColor);
    canvas.drawCircle(const Offset(78, 62), 4, Paint()..color = roofColor);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w900,
          fontFamily: 'Tajawal',
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: 48);
    textPainter.paint(canvas, Offset(56 - textPainter.width / 2, 40));

    final bytes =
        await _pictureToBytes(recorder, width.toInt(), height.toInt());
    return BitmapDescriptor.bytes(bytes, width: 56, height: 41);
  }

  Future<Uint8List> _pictureToBytes(
    ui.PictureRecorder recorder,
    int width,
    int height,
  ) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
