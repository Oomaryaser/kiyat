import 'dart:async';
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
    );
  }
}

class DriverTrackingNotifier extends Notifier<DriverTrackingState> {
  StreamSubscription<Position>? _positionSubscription;
  Timer? _waitsTimer;

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
    final routeGuidance = stops.length < 2
        ? null
        : DriverRouteGuidance.fromStops(
            stops: stops,
            position: LatLng(position.latitude, position.longitude),
            thresholdMeters: 35,
          );

    final repo = ref.read(driverRepositoryProvider);
    final vehicle = state.vehicle;
    if (vehicle == null) return;

    if (routeGuidance?.isOffRoute == true) {
      if (state.isServerTrackingActive) {
        try {
          await repo.stopVehicleTracking(vehicle.id);
        } catch (_) {}
      }
      state = state.copyWith(
        lastPosition: position,
        isServerTrackingActive: false,
        statusMessage: 'روح لأقرب نقطة على الخط علمود يبدأ التتبع مالتك.',
      );
      return;
    }

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
        statusMessage: 'التتبع شغال والركاب يشوفون كيتك.',
      );
    } catch (e) {
      state = state.copyWith(
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
}

final driverTrackingProvider = NotifierProvider<DriverTrackingNotifier, DriverTrackingState>(() {
  return DriverTrackingNotifier();
});
