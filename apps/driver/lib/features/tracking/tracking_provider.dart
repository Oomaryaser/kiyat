import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../driver_repository.dart';
import '../../core/utils/location_helper.dart';
import 'driver_route_guidance.dart';

class DriverTrackingState {
  final DriverRoute? route;
  final DriverVehicle? vehicle;
  final Position? lastPosition;
  final List<PassengerWaitPoint> waits;
  final bool isTracking;
  final bool isServerTrackingActive;
  final String? statusMessage;
  final bool loadingDetail;
  final DriverRouteDetail? routeDetail;
  final bool isSimulating;
  final List<LatLng> roadRoute;

  const DriverTrackingState({
    this.route,
    this.vehicle,
    this.lastPosition,
    this.waits = const [],
    this.isTracking = false,
    this.isServerTrackingActive = false,
    this.statusMessage,
    this.loadingDetail = false,
    this.routeDetail,
    this.isSimulating = false,
    this.roadRoute = const [],
  });

  DriverTrackingState copyWith({
    DriverRoute? route,
    DriverVehicle? vehicle,
    Position? lastPosition,
    List<PassengerWaitPoint>? waits,
    bool? isTracking,
    bool? isServerTrackingActive,
    String? statusMessage,
    bool? loadingDetail,
    DriverRouteDetail? routeDetail,
    bool? isSimulating,
    List<LatLng>? roadRoute,
  }) {
    return DriverTrackingState(
      route: route ?? this.route,
      vehicle: vehicle ?? this.vehicle,
      lastPosition: lastPosition ?? this.lastPosition,
      waits: waits ?? this.waits,
      isTracking: isTracking ?? this.isTracking,
      isServerTrackingActive: isServerTrackingActive ?? this.isServerTrackingActive,
      statusMessage: statusMessage ?? this.statusMessage,
      loadingDetail: loadingDetail ?? this.loadingDetail,
      routeDetail: routeDetail ?? this.routeDetail,
      isSimulating: isSimulating ?? this.isSimulating,
      roadRoute: roadRoute ?? this.roadRoute,
    );
  }
}

class DriverTrackingNotifier extends Notifier<DriverTrackingState> {
  StreamSubscription<Position>? _positionSubscription;
  Timer? _waitsTimer;
  Timer? _simulationTimer;

  @override
  DriverTrackingState build() {
    ref.onDispose(() {
      _positionSubscription?.cancel();
      _waitsTimer?.cancel();
    });
    return const DriverTrackingState();
  }

  Future<void> startTracking(DriverRoute route, String plateNumber) async {
    state = DriverTrackingState(
      route: route,
      isTracking: true,
      statusMessage: 'دا نطلب صلاحية الموقع...',
    );

    final repo = ref.read(driverRepositoryProvider);
    try {
      final vehicle = await repo.createVehicle(
        routeId: route.id,
        plateNumber: plateNumber.isEmpty ? 'كية' : plateNumber,
      );
      state = state.copyWith(vehicle: vehicle, loadingDetail: true);

      final routeDetail = await repo.routeDetail(route.id);
      state = state.copyWith(
        routeDetail: routeDetail,
        loadingDetail: false,
      );

      final roadRoute = await _loadTransitRoadRoute(routeDetail.stops);
      state = state.copyWith(roadRoute: roadRoute);

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = state.copyWith(
          isTracking: false,
          statusMessage: 'خدمة الموقع مطفية. شغلها حتى تبدي التتبع.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          isTracking: false,
          statusMessage: 'نحتاج صلاحية الموقع حتى يشوفك الراكب.',
        );
        return;
      }

      await repo.connectSocket();
      final firstPosition = await KiyatLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _sendPosition(firstPosition);

      _waitsTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _loadPassengerWaits(),
      );
      await _loadPassengerWaits();

      _positionSubscription = KiyatLocation.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 18,
        ),
      ).listen(_sendPosition);

    } catch (e) {
      state = state.copyWith(
        isTracking: false,
        statusMessage: e is DriverRepositoryException
            ? e.message
            : 'ما قدرنا نشغل التتبع. جرّب مرة ثانية.',
      );
    }
  }

  Future<void> _sendPosition(Position position) async {
    final routeDetail = state.routeDetail;
    final stops = routeDetail?.stops ?? const [];
    
    // Snapping calculation
    final currentPos = LatLng(position.latitude, position.longitude);
    DriverRouteGuidance? routeGuidance;
    if (state.roadRoute.isNotEmpty) {
      routeGuidance = DriverRouteGuidance.fromPoints(
        points: state.roadRoute,
        position: currentPos,
        thresholdMeters: 35,
      );
    } else if (stops.length >= 2) {
      routeGuidance = DriverRouteGuidance.fromStops(
        stops: stops,
        position: currentPos,
        thresholdMeters: 35,
      );
    }

    final repo = ref.read(driverRepositoryProvider);
    final vehicle = state.vehicle;
    if (vehicle == null) return;

    final isOffRoute = routeGuidance?.isOffRoute == true;

    try {
      final socket = repo.socket;
      if (socket != null && socket.connected) {
        repo.sendLocationViaSocket(
          vehicleId: vehicle.id,
          lat: position.latitude,
          lng: position.longitude,
          speedMetersPerSecond: position.speed.isFinite && position.speed >= 0
              ? position.speed
              : null,
        );
      } else {
        await repo.updateVehicleLocation(
          vehicleId: vehicle.id,
          lat: position.latitude,
          lng: position.longitude,
          speedMetersPerSecond: position.speed.isFinite && position.speed >= 0
              ? position.speed
              : null,
        );
      }
      state = state.copyWith(
        lastPosition: position,
        isServerTrackingActive: true,
        statusMessage: isOffRoute
            ? 'روح لأقرب نقطة على الخط علمود يبدأ التتبع مالتك.'
            : 'التتبع شغال والركاب يشوفون كيتك.',
      );
    } catch (e) {
      state = state.copyWith(
        lastPosition: position,
        statusMessage: e is DriverRepositoryException ? e.message : 'فشل تحديث الموقع.',
      );
    }
  }

  Future<void> _loadPassengerWaits() async {
    final route = state.route;
    if (route == null) return;
    try {
      final next = await ref.read(driverRepositoryProvider).activePassengerWaits(route.id);
      state = state.copyWith(waits: next);
    } catch (_) {
      state = state.copyWith(statusMessage: 'ما قدرنا نحدث ركاب الانتظار.');
    }
  }

  Future<void> stopTracking() async {
    final vehicle = state.vehicle;
    if (vehicle == null) return;
    
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _waitsTimer?.cancel();
    _waitsTimer = null;

    final repo = ref.read(driverRepositoryProvider);
    try {
      repo.disconnectSocket();
      await repo.stopVehicleTracking(vehicle.id);
    } catch (_) {}

    state = const DriverTrackingState();
  }

  Future<void> startSimulationToNearestPassenger() async {
    final position = state.lastPosition;
    if (position == null) return;
    final currentPos = LatLng(position.latitude, position.longitude);

    LatLng target;
    if (state.waits.isNotEmpty) {
      final sorted = [...state.waits];
      sorted.sort((a, b) {
        final distanceA = Geolocator.distanceBetween(currentPos.latitude, currentPos.longitude, a.lat, a.lng);
        final distanceB = Geolocator.distanceBetween(currentPos.latitude, currentPos.longitude, b.lat, b.lng);
        return distanceA.compareTo(distanceB);
      });
      target = LatLng(sorted.first.lat, sorted.first.lng);
    } else {
      final stops = state.routeDetail?.stops ?? const [];
      if (stops.isEmpty) return;
      target = LatLng(stops.first.lat, stops.first.lng);
    }

    try {
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/${currentPos.longitude},${currentPos.latitude};${target.longitude},${target.latitude}',
        {'overview': 'full', 'geometries': 'geojson'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
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

      if (points.isEmpty) return;

      _simulationTimer?.cancel();
      int index = 0;
      state = state.copyWith(isSimulating: true);

      _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (index >= points.length) {
          timer.cancel();
          _simulationTimer = null;
          state = state.copyWith(isSimulating: false);
          return;
        }
        final pt = points[index];
        final nextPos = Position(
          latitude: pt.latitude,
          longitude: pt.longitude,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 10.0,
          speedAccuracy: 0.0,
        );
        _sendPosition(nextPos);
        index++;
      });
    } catch (_) {
      state = state.copyWith(isSimulating: false);
    }
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    state = state.copyWith(isSimulating: false);
  }

  Future<List<LatLng>> _loadTransitRoadRoute(List<DriverStop> stops) async {
    if (stops.length < 2) return const [];
    try {
      final coordsString = stops
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
        return coordinates
            .whereType<List<dynamic>>()
            .where((point) => point.length >= 2)
            .map(
              (point) => LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ),
            )
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}

final driverTrackingProvider = NotifierProvider<DriverTrackingNotifier, DriverTrackingState>(() {
  return DriverTrackingNotifier();
});
