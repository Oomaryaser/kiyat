import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/transit_models.dart';

/// Base URL for the Kiyat backend API.
const _apiBase = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:3000',
);

class LiveRouteMap extends StatefulWidget {
  const LiveRouteMap({
    super.key,
    required this.stops,
    required this.vehicles,
    required this.pickupStop,
    required this.selectedVehicle,
    this.compact = false,
    this.extraRouteLines = const [],
    this.userLocation,
    this.nearestRoutePoint,
  });

  final List<TransitStop> stops;
  final List<VehicleArrivalEstimate> vehicles;
  final TransitStop? pickupStop;
  final VehicleArrivalEstimate? selectedVehicle;
  final bool compact;
  final List<List<TransitStop>> extraRouteLines;
  final LatLng? userLocation;
  final LatLng? nearestRoutePoint;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap>
    with SingleTickerProviderStateMixin {
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

  // ── Walking route state ───────────────────────────────────────────────────
  List<LatLng> _walkingRoute = const [];
  LatLng? _lastFetchLocation;
  LatLng? _lastFetchNearestRoutePoint;
  DateTime? _lastFetchTime;
  bool _walkingRouteFetching = false;
  int? _walkingMinutes;
  int? _walkingDistanceMeters;

  // ── Camera auto-tracking state ────────────────────────────────────────────
  /// When false the user has manually dragged the map; auto-pan is suspended.
  bool _autoCameraEnabled = true;

  @override
  void initState() {
    super.initState();
    _ensurePulseController();
    _loadMarkerIcons();
    _loadGoogleRoute();
    if (widget.userLocation != null && widget.nearestRoutePoint != null) {
      _loadWalkingRoute();
    }
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
    // Throttled walking route re-fetch.
    final user = widget.userLocation;
    final target = widget.nearestRoutePoint;
    if (user != null && target != null) {
      final movedEnough = _lastFetchLocation == null ||
          Geolocator.distanceBetween(
                user.latitude,
                user.longitude,
                _lastFetchLocation!.latitude,
                _lastFetchLocation!.longitude,
              ) >
              20;
      final targetShifted = _lastFetchNearestRoutePoint == null ||
          Geolocator.distanceBetween(
                target.latitude,
                target.longitude,
                _lastFetchNearestRoutePoint!.latitude,
                _lastFetchNearestRoutePoint!.longitude,
              ) >
              5;
      final stale = _lastFetchTime == null ||
          DateTime.now().difference(_lastFetchTime!) >
              const Duration(seconds: 15);
      if (movedEnough || targetShifted || stale) {
        _loadWalkingRoute();
      }
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

    // Walking polyline: use real road route if available, else straight line.
    final walkingPolyline = _walkingRoute.isNotEmpty
        ? _walkingRoute
        : (widget.userLocation != null && widget.nearestRoutePoint != null
            ? [widget.userLocation!, widget.nearestRoutePoint!]
            : <LatLng>[]);

    final showWalkingPath = walkingPolyline.length >= 2;
    final showRecenterButton =
        !_autoCameraEnabled && widget.userLocation != null && widget.nearestRoutePoint != null;

    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 8 : 0),
        child: Stack(
          children: [
            // ── Detect user drag to pause auto-camera ──────────────────────
            Listener(
              onPointerDown: (_) {
                if (_autoCameraEnabled) {
                  setState(() => _autoCameraEnabled = false);
                }
              },
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                    target: center, zoom: widget.compact ? 14.6 : 13.4),
                onMapCreated: (controller) {
                  _controller = controller;
                  _animateCameraToWalkingOrFit(routePoints);
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
                  if (showWalkingPath)
                    Polyline(
                      polylineId: const PolylineId('walking_to_route'),
                      points: walkingPolyline,
                      color: Colors.green.shade600,
                      width: 4,
                      patterns: [PatternItem.dash(12), PatternItem.gap(8)],
                      zIndex: 3,
                    ),
                },
              ),
            ),

            // ── Re-center floating button ─────────────────────────────────
            if (showRecenterButton)
              Positioned(
                bottom: 16,
                left: 16,
                child: _RecenterButton(
                  onTap: () {
                    setState(() => _autoCameraEnabled = true);
                    _animateCameraToWalkingOrFit(routePoints);
                  },
                ),
              ),
            if (showWalkingPath && (_walkingMinutes != null || _walkingDistanceMeters != null))
              Positioned(
                top: 12,
                right: 12,
                child: _WalkingEtaBadge(
                  minutes: _walkingMinutes,
                  distanceMeters: _walkingDistanceMeters,
                ),
              ),
          ],
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

    if (widget.userLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_actual_location'),
          position: widget.userLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'موقعك الفعلي'),
          zIndexInt: 11,
        ),
      );
    }

    if (widget.pickupStop != null && pickupIcon != null) {
      final pickupPosition = widget.nearestRoutePoint ?? LatLng(widget.pickupStop!.lat, widget.pickupStop!.lng);
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_location'),
          position: pickupPosition,
          icon: pickupIcon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(
              title: 'نقطة الصعود', snippet: 'نقطة صعودك للخط'),
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
    if (widget.stops.length < 2) {
      if (!mounted) return;
      setState(() => _roadRoute = fallback);
      return;
    }

    // Try OSRM routing first
    try {
      final coordsString = widget.stops
          .map((stop) => '${stop.lng},${stop.lat}')
          .join(';');
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/$coordsString',
        {'overview': 'full', 'geometries': 'geojson'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>? ?? const [];
        final geometry = routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List<dynamic>? ?? const [];
        final points = coordinates
            .whereType<List<dynamic>>()
            .where((point) => point.length >= 2)
            .map(
              (point) => LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ),
            )
            .toList();
        if (points.length > 1) {
          if (!mounted) return;
          setState(() => _roadRoute = points);
          await _fitCamera(points);
          return;
        }
      }
    } catch (_) {
      // Ignore and fallback to Google Directions or straight lines
    }

    // Fallback to Google Directions if API Key is available
    const googleMapsKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
    if (googleMapsKey.isNotEmpty) {
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
        'key': googleMapsKey,
        if (waypoints != null) 'waypoints': waypoints,
      };
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/directions/json', query);

      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final routes = data['routes'] as List<dynamic>?;
          final encoded =
              routes?.firstOrNull?['overview_polyline']?['points'] as String?;
          if (encoded != null && encoded.isNotEmpty) {
            final decoded = _decodePolyline(encoded);
            if (decoded.isNotEmpty) {
              if (!mounted) return;
              setState(() => _roadRoute = decoded);
              await _fitCamera(decoded);
              return;
            }
          }
        }
      } catch (_) {}
    }

    // Ultimate fallback: straight lines connecting stops
    if (!mounted) return;
    setState(() => _roadRoute = fallback);
    await _fitCamera(fallback);
  }

  /// Choose camera target: walking path (when off-route) or full transit route.
  Future<void> _animateCameraToWalkingOrFit(List<LatLng> routePoints) async {
    if (!_autoCameraEnabled) return;
    final controller = _controller;
    if (controller == null) return;

    final user = widget.userLocation;
    final target = widget.nearestRoutePoint;

    // When the passenger is still walking to the route, focus on walking path.
    if (user != null && target != null) {
      final distToRoute = Geolocator.distanceBetween(
        user.latitude, user.longitude,
        target.latitude, target.longitude,
      );
      if (distToRoute > 10) {
        final path = _walkingRoute.isNotEmpty
            ? _walkingRoute
            : [user, target];
        if (path.length >= 2) {
          await controller.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsFor(path), 60),
          );
          return;
        }
      }
    }

    // Default: fit the full transit route + vehicles.
    if (routePoints.length < 2) return;
    final points = [
      ...routePoints,
      if (widget.pickupStop != null)
        LatLng(widget.pickupStop!.lat, widget.pickupStop!.lng),
      ...widget.vehicles.map((vehicle) => LatLng(vehicle.lat, vehicle.lng)),
    ];
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(_boundsFor(points), widget.compact ? 24 : 56),
    );
  }

  /// Legacy alias kept for OSRM/Google route load callbacks.
  Future<void> _fitCamera(List<LatLng> routePoints) =>
      _animateCameraToWalkingOrFit(routePoints);

  // ── Walking route from backend ──────────────────────────────────────────────

  Future<void> _loadWalkingRoute() async {
    final user = widget.userLocation;
    final target = widget.nearestRoutePoint;
    if (user == null || target == null || _walkingRouteFetching) return;

    _walkingRouteFetching = true;
    _lastFetchLocation = user;
    _lastFetchNearestRoutePoint = target;
    _lastFetchTime = DateTime.now();

    try {
      final uri = Uri.parse(
        '$_apiBase/tracking/walking-route'
        '?fromLat=${user.latitude}'
        '&fromLng=${user.longitude}'
        '&toLat=${target.latitude}'
        '&toLng=${target.longitude}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawPoints = data['points'] as List<dynamic>? ?? const [];
        final points = rawPoints
            .whereType<Map<String, dynamic>>()
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();
        if (points.length > 1 && mounted) {
          setState(() {
            _walkingRoute = points;
            _walkingMinutes = (data['walkingMinutes'] as num?)?.toInt();
            _walkingDistanceMeters = (data['distanceMeters'] as num?)?.toInt();
          });
          // Focus camera on the real walking path.
          final routePoints = _roadRoute.isEmpty
              ? widget.stops.map((s) => LatLng(s.lat, s.lng)).toList()
              : _roadRoute;
          await _animateCameraToWalkingOrFit(routePoints);
        }
      }
    } catch (_) {
      // Silently keep the current (possibly straight-line) fallback.
    } finally {
      if (mounted) {
        _walkingRouteFetching = false;
      }
    }
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

// ── Re-center Button ──────────────────────────────────────────────────────────

/// A premium floating button that re-enables auto camera tracking.
class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E8B),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B5E8B).withValues(alpha: 0.38),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.my_location_rounded, color: Colors.white, size: 17),
            SizedBox(width: 6),
            Text(
              'توسيط المسار',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Tajawal',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalkingEtaBadge extends StatelessWidget {
  const _WalkingEtaBadge({
    required this.minutes,
    required this.distanceMeters,
  });

  final int? minutes;
  final int? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceMeters == null
        ? null
        : distanceMeters! >= 1000
            ? '${(distanceMeters! / 1000).toStringAsFixed(1)} كم'
            : '$distanceMeters م';
    final text = [
      if (minutes != null) '$minutes دقيقة مشياً',
      if (distanceText != null) distanceText,
    ].join(' • ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_walk, size: 17, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF173244),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFamily: 'Tajawal',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
