import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_utils/shared_utils.dart';

import '../../driver_repository.dart';
import '../../shared/widgets/state_panel.dart';
import 'driver_route_guidance.dart';

class DriverMapBanner extends StatelessWidget {
  const DriverMapBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.orange.shade900),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.center_focus_strong),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverTrackingMap extends StatefulWidget {
  const DriverTrackingMap({
    super.key,
    required this.stops,
    required this.waits,
    required this.lastPosition,
    required this.routeName,
    required this.routeSnapThresholdMeters,
  });

  final List<DriverStop> stops;
  final List<PassengerWaitPoint> waits;
  final Position? lastPosition;
  final String routeName;
  final double routeSnapThresholdMeters;

  @override
  State<DriverTrackingMap> createState() => _DriverTrackingMapState();
}

class _DriverTrackingMapState extends State<DriverTrackingMap> {
  GoogleMapController? controller;
  String? focusedWaitId;
  String? routeRequestKey;
  List<LatLng> roadToWait = const [];
  bool roadRouteLoaded = false;
  List<LatLng> roadRoute = const [];
  final Map<String, BitmapDescriptor> _passengerIcons = {};
  BitmapDescriptor? _majorStopIcon;
  BitmapDescriptor? _minorStopIcon;

  @override
  void initState() {
    super.initState();
    _loadTransitRoadRoute();
    _updatePassengerIcons();
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
      Paint()..color = Colors.white.withOpacity(0.9),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(bytes, width: size / 2, height: size / 2);
  }

  Future<void> _updatePassengerIcons() async {
    bool changed = false;
    if (_majorStopIcon == null) {
      _majorStopIcon = await _buildStopDotIcon(const Color(0xFF1B5E8B), 28);
      changed = true;
    }
    if (_minorStopIcon == null) {
      _minorStopIcon = await _buildStopDotIcon(const Color(0xFF7BA9C6), 22);
      changed = true;
    }

    final nearestWait = _nearestWait;
    for (int i = 0; i < widget.waits.length; i++) {
      final wait = widget.waits[i];
      final isNearest = wait.id == nearestWait?.id;
      final number = i + 1;
      final cacheKey = '${wait.id}_${number}_$isNearest';
      if (!_passengerIcons.containsKey(cacheKey)) {
        try {
          final icon = await _buildPassengerDotIcon(number, isNearest);
          _passengerIcons[cacheKey] = icon;
          changed = true;
        } catch (_) {}
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<BitmapDescriptor> _buildPassengerDotIcon(int number, bool isNearest) async {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    // 1. Shadow/Outer glow
    final shadowColor = isNearest
        ? const Color(0xFFFF5722).withOpacity(0.38)
        : Colors.black.withOpacity(0.18);
    canvas.drawCircle(
      center,
      28,
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 2. White outer border
    canvas.drawCircle(
      center,
      21,
      Paint()..color = Colors.white,
    );

    // 3. Main colored circle
    final mainColor = isNearest ? const Color(0xFFFF5722) : const Color(0xFF1B5E8B);
    canvas.drawCircle(
      center,
      17,
      Paint()..color = mainColor,
    );

    // 4. Number text centered
    final textSpan = TextSpan(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        fontFamily: 'Tajawal',
      ),
      text: '$number',
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(bytes, width: size / 2, height: size / 2);
  }

  @override
  void didUpdateWidget(covariant DriverTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePassengerIcons();
    final routeGuidance = _routeGuidance;
    final isOffRoute = routeGuidance?.isOffRoute == true;
    final nearestWait = isOffRoute ? null : _nearestWait;
    final positionChanged =
        oldWidget.lastPosition?.latitude != widget.lastPosition?.latitude ||
        oldWidget.lastPosition?.longitude != widget.lastPosition?.longitude;
    final waitsChanged =
        oldWidget.waits.map((wait) => wait.id).join(',') !=
        widget.waits.map((wait) => wait.id).join(',');

    if (oldWidget.stops.map((s) => '${s.lat},${s.lng}').join(',') !=
        widget.stops.map((s) => '${s.lat},${s.lng}').join(',')) {
      _loadTransitRoadRoute();
    }

    if (isOffRoute && routeGuidance != null && positionChanged) {
      routeRequestKey = null;
      roadToWait = const [];
      roadRouteLoaded = false;
      _focusOnRoutePoint(routeGuidance);
      return;
    }

    if (nearestWait != null &&
        (focusedWaitId != nearestWait.id || positionChanged)) {
      _focusOnWait(nearestWait);
      _loadRoadToWait(nearestWait);
      return;
    }
    if (waitsChanged || positionChanged) {
      _focusBestTarget();
      if (nearestWait != null) _loadRoadToWait(nearestWait);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _initialCenter;
    if (center == null) {
      return const StatePanel(
        icon: Icons.map_outlined,
        title: 'الخريطة تنتظر الموقع',
        message: 'أول ما يوصل موقع الكية راح تظهر الخريطة هنا.',
      );
    }

    final colors = Theme.of(context).colorScheme;
    final routeGuidance = _routeGuidance;
    final isOffRoute = routeGuidance?.isOffRoute == true;
    final nearestWait = isOffRoute ? null : _nearestWait;
    final distance = nearestWait == null ? null : _distanceToWait(nearestWait);
    final roadPoints = isOffRoute
        ? _routeGuidancePoints(routeGuidance)
        : _guidancePoints(nearestWait);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: (nextController) {
              controller = nextController;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusBestTarget();
              });
            },
            initialCameraPosition: CameraPosition(target: center, zoom: 14.8),
            mapType: MapType.normal,
            buildingsEnabled: true,
            trafficEnabled: false,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
            markers: _markers,
            polylines: {
              if (widget.stops.length > 1) ...[
                Polyline(
                  polylineId: const PolylineId('route_path_shadow'),
                  points: roadRoute.isNotEmpty
                      ? roadRoute
                      : widget.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList(),
                  color: Colors.white,
                  width: 8,
                  zIndex: 1,
                ),
                Polyline(
                  polylineId: const PolylineId('route_path'),
                  points: roadRoute.isNotEmpty
                      ? roadRoute
                      : widget.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList(),
                  color: colors.primary.withValues(alpha: 0.82),
                  width: 5,
                  zIndex: 2,
                ),
              ],
              if (widget.lastPosition != null &&
                  (nearestWait != null || isOffRoute) &&
                  roadPoints.length > 1)
                Polyline(
                  polylineId: PolylineId(
                    isOffRoute
                        ? 'driver_to_route_start'
                        : 'driver_to_nearest_wait',
                  ),
                  points: roadPoints,
                  color: Colors.orange.shade800,
                  width: 7,
                  zIndex: 6,
                  patterns: !isOffRoute && roadRouteLoaded
                      ? const []
                      : [PatternItem.dash(18), PatternItem.gap(10)],
                ),
            },
            circles: {
              if (isOffRoute && routeGuidance != null)
                Circle(
                  circleId: const CircleId('route_start_area'),
                  center: routeGuidance.nearestPoint,
                  radius: 55,
                  fillColor: Colors.orange.withValues(alpha: 0.16),
                  strokeColor: Colors.orange.shade800,
                  strokeWidth: 3,
                ),
              if (nearestWait != null)
                Circle(
                  circleId: const CircleId('nearest_wait_area'),
                  center: LatLng(nearestWait.lat, nearestWait.lng),
                  radius: 85,
                  fillColor: Colors.orange.withValues(alpha: 0.16),
                  strokeColor: Colors.orange.shade800,
                  strokeWidth: 3,
                ),
              if (widget.lastPosition != null)
                Circle(
                  circleId: const CircleId('driver_area'),
                  center: LatLng(
                    widget.lastPosition!.latitude,
                    widget.lastPosition!.longitude,
                  ),
                  radius: 70,
                  fillColor: colors.primary.withValues(alpha: 0.14),
                  strokeColor: colors.primary.withValues(alpha: 0.36),
                  strokeWidth: 2,
                ),
            },
          ),
          if (isOffRoute && routeGuidance != null)
            PositionedDirectional(
              start: 10,
              end: 10,
              top: 10,
              child: DriverMapBanner(
                icon: Icons.navigation,
                title: 'روح لهنا',
                message:
                    'يبعد ${_formatDistance(routeGuidance.distanceMeters)} عن الخط، حتى يبدأ التتبع مالتك.',
                onTap: () => _focusOnRoutePoint(routeGuidance),
              ),
            )
          else if (nearestWait != null)
            PositionedDirectional(
              start: 10,
              end: 10,
              top: 10,
              child: DriverMapBanner(
                icon: Icons.navigation,
                title: 'روح لهنا',
                message: distance == null
                    ? 'أقرب راكب محدد على الخريطة'
                    : roadRouteLoaded
                        ? 'طريق الشوارع إلى أقرب راكب، يبعد ${_formatDistance(distance)}'
                        : 'خط مباشر مؤقت، يبعد ${_formatDistance(distance)}',
                onTap: () => _focusOnWait(nearestWait),
              ),
            ),
        ],
      ),
    );
  }

  LatLng? get _initialCenter {
    final routeGuidance = _routeGuidance;
    if (routeGuidance?.isOffRoute == true) {
      return routeGuidance!.nearestPoint;
    }
    final nearestWait = _nearestWait;
    if (nearestWait != null) {
      return LatLng(nearestWait.lat, nearestWait.lng);
    }
    if (widget.lastPosition != null) {
      return LatLng(
        widget.lastPosition!.latitude,
        widget.lastPosition!.longitude,
      );
    }
    if (widget.stops.isNotEmpty) {
      return LatLng(widget.stops.first.lat, widget.stops.first.lng);
    }
    if (widget.waits.isNotEmpty) {
      return LatLng(widget.waits.first.lat, widget.waits.first.lng);
    }
    return null;
  }

  Set<Marker> get _markers {
    final routeGuidance = _routeGuidance;
    final isOffRoute = routeGuidance?.isOffRoute == true;
    final nearestWait = isOffRoute ? null : _nearestWait;
    final markers = <Marker>{};

    for (final stop in widget.stops) {
      // Skip rendering the stop if there is a passenger wait at the exact same location
      final hasWait = widget.waits.any((w) =>
          (w.lat - stop.lat).abs() < 0.0001 &&
          (w.lng - stop.lng).abs() < 0.0001);
      if (hasWait) continue;

      markers.add(
        Marker(
          markerId: MarkerId('stop_${stop.id}'),
          position: LatLng(stop.lat, stop.lng),
          anchor: const Offset(0.5, 0.5),
          icon: stop.isMajor
              ? (_majorStopIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure))
              : (_minorStopIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan)),
          infoWindow: InfoWindow(
            title: stop.nameAr,
            snippet: stop.landmarkAr.isEmpty
                ? widget.routeName
                : stop.landmarkAr,
          ),
          zIndexInt: stop.isMajor ? 4 : 3,
        ),
      );
    }

    for (final wait in widget.waits) {
      markers.add(
        Marker(
          markerId: MarkerId('wait_${wait.id}'),
          position: LatLng(wait.lat, wait.lng),
          anchor: const Offset(0.5, 0.5),
          icon: _passengerIcons['${wait.id}_${widget.waits.indexOf(wait) + 1}_${wait.id == nearestWait?.id}'] ??
              BitmapDescriptor.defaultMarkerWithHue(
                wait.id == nearestWait?.id
                    ? BitmapDescriptor.hueOrange
                    : BitmapDescriptor.hueYellow,
              ),
          infoWindow: InfoWindow(
            title: wait.id == nearestWait?.id
                ? 'روح لهنا • راكب ${widget.waits.indexOf(wait) + 1}'
                : 'راكب ${widget.waits.indexOf(wait) + 1} ينتظر',
            snippet: 'ظاهر للسائقين',
          ),
          zIndexInt: wait.id == nearestWait?.id ? 14 : 8,
        ),
      );
    }

    if (isOffRoute && routeGuidance != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('route_start_target'),
          position: routeGuidance.nearestPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(
            title: 'روح لهنا',
            snippet: 'أقرب نقطة على الخط حتى يبدأ التتبع',
          ),
          zIndexInt: 16,
        ),
      );
    }

    if (widget.lastPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_vehicle'),
          position: LatLng(
            widget.lastPosition!.latitude,
            widget.lastPosition!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'موقع كيتك الحالي'),
          zIndexInt: 12,
        ),
      );
    }

    return markers;
  }

  PassengerWaitPoint? get _nearestWait {
    if (widget.waits.isEmpty) return null;
    final sorted = [...widget.waits];
    sorted.sort((a, b) {
      final distanceA = _distanceToWait(a) ?? 0;
      final distanceB = _distanceToWait(b) ?? 0;
      return distanceA.compareTo(distanceB);
    });
    return sorted.first;
  }

  double? _distanceToWait(PassengerWaitPoint wait) {
    final position = widget.lastPosition;
    if (position == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      wait.lat,
      wait.lng,
    );
  }

  DriverRouteGuidance? get _routeGuidance {
    final position = widget.lastPosition;
    if (position == null || widget.stops.length < 2) return null;
    return DriverRouteGuidance.fromStops(
      stops: widget.stops,
      position: LatLng(position.latitude, position.longitude),
      thresholdMeters: widget.routeSnapThresholdMeters,
    );
  }

  void _focusBestTarget() {
    final routeGuidance = _routeGuidance;
    if (routeGuidance?.isOffRoute == true) {
      _focusOnRoutePoint(routeGuidance!);
      return;
    }
    final nearestWait = _nearestWait;
    if (nearestWait != null) {
      _focusOnWait(nearestWait);
      _loadRoadToWait(nearestWait);
      return;
    }
    final position = widget.lastPosition;
    if (position != null) {
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    }
  }

  void _focusOnRoutePoint(DriverRouteGuidance guidance) {
    final position = widget.lastPosition;
    if (position == null) {
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(guidance.nearestPoint, 16),
      );
      return;
    }
    controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        _boundsFor([
          LatLng(position.latitude, position.longitude),
          guidance.nearestPoint,
        ]),
        72,
      ),
    );
  }

  void _focusOnWait(PassengerWaitPoint wait) {
    focusedWaitId = wait.id;
    final position = widget.lastPosition;
    if (position == null) {
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(wait.lat, wait.lng), 16),
      );
      return;
    }
    final bounds = _boundsFor([
      LatLng(position.latitude, position.longitude),
      LatLng(wait.lat, wait.lng),
      ...roadToWait,
    ]);
    controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  List<LatLng> _guidancePoints(PassengerWaitPoint? wait) {
    final position = widget.lastPosition;
    if (position == null || wait == null) return const [];
    if (roadToWait.length > 1) return roadToWait;
    return [
      LatLng(position.latitude, position.longitude),
      LatLng(wait.lat, wait.lng),
    ];
  }

  List<LatLng> _routeGuidancePoints(DriverRouteGuidance? guidance) {
    final position = widget.lastPosition;
    if (position == null || guidance == null) return const [];
    return [
      LatLng(position.latitude, position.longitude),
      guidance.nearestPoint,
    ];
  }

  Future<void> _loadRoadToWait(PassengerWaitPoint wait) async {
    final position = widget.lastPosition;
    if (position == null) return;
    final requestKey = [
      position.latitude.toStringAsFixed(5),
      position.longitude.toStringAsFixed(5),
      wait.lat.toStringAsFixed(5),
      wait.lng.toStringAsFixed(5),
    ].join(',');
    if (routeRequestKey == requestKey) return;
    routeRequestKey = requestKey;

    final fallback = [
      LatLng(position.latitude, position.longitude),
      LatLng(wait.lat, wait.lng),
    ];
    try {
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/${position.longitude},${position.latitude};${wait.lng},${wait.lat}',
        {'overview': 'full', 'geometries': 'geojson'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        _setRoadRoute(fallback, loaded: false);
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>? ?? const [];
      final geometry = routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
      final coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? const [];
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
      _setRoadRoute(
        points.length > 1 ? points : fallback,
        loaded: points.length > 1,
      );
    } catch (_) {
      _setRoadRoute(fallback, loaded: false);
    }
  }

  void _setRoadRoute(List<LatLng> points, {required bool loaded}) {
    if (!mounted) return;
    setState(() {
      roadToWait = points;
      roadRouteLoaded = loaded;
    });
    final controller = this.controller;
    if (controller != null && points.length > 1) {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFor(points), 72),
      );
    }
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final point in points.skip(1)) {
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
    }
    if (south == north) {
      south -= 0.001;
      north += 0.001;
    }
    if (west == east) {
      west -= 0.001;
      east += 0.001;
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Future<void> _loadTransitRoadRoute() async {
    if (widget.stops.length < 2) return;
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
        if (points.length > 1 && mounted) {
          setState(() {
            roadRoute = points;
          });
        }
      }
    } catch (_) {}
  }
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${toArabicDigits(meters.round())} م';
  return '${toArabicDigits((meters / 1000).toStringAsFixed(1))} كم';
}
