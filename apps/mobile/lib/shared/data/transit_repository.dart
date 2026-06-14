import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../models/transit_models.dart';

final transitRepositoryProvider = Provider<TransitRepository>((ref) {
  return TransitRepository(ref.watch(apiClientProvider));
});

final routesProvider = FutureProvider<List<TransitRoute>>((ref) async {
  return ref.watch(transitRepositoryProvider).listRoutes();
});

final routeDetailProvider =
    FutureProvider.family<TransitRouteDetail, String>((ref, routeId) async {
  return ref.watch(transitRepositoryProvider).routeDetail(routeId);
});

final routeDetailsProvider =
    FutureProvider<List<TransitRouteDetail>>((ref) async {
  final repository = ref.watch(transitRepositoryProvider);
  final routes = await repository.listRoutes();
  final details = await Future.wait(
    routes.map((route) => repository.routeDetail(route.id)),
  );
  final seen = <String>{};
  return details.where((detail) {
    if (detail.stops.isEmpty || seen.contains(detail.route.id)) return false;
    seen.add(detail.route.id);
    return true;
  }).toList();
});

final routeArrivalProvider =
    FutureProvider.family<RouteArrivalSnapshot, RouteArrivalRequest>(
        (ref, request) async {
  return ref.watch(transitRepositoryProvider).routeArrival(request);
});

final activeWaitRouteIdProvider = FutureProvider<String?>((ref) async {
  return ref.watch(transitRepositoryProvider).loadActiveWaitRouteId();
});

final savedRouteIdsProvider = FutureProvider<Set<String>>((ref) async {
  return ref.watch(transitRepositoryProvider).loadSavedRouteIds();
});

class TransitRepository {
  const TransitRepository(this._dio);

  final Dio _dio;

  Future<List<TransitRoute>> listRoutes() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/routes');
      final data = response.data?['data'] as List<dynamic>? ?? const [];
      final routes = data
          .whereType<Map<String, dynamic>>()
          .map(TransitRoute.fromJson)
          .toList();
      return routes.isEmpty ? _fallbackRoutes : routes;
    } catch (_) {
      return _fallbackRoutes;
    }
  }

  Future<TransitRouteDetail> routeDetail(String routeId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/routes/$routeId');
      final detail = TransitRouteDetail.fromJson(response.data ?? const {});
      if (detail.stops.isEmpty) return _fallbackDetail;
      return detail;
    } catch (_) {
      return _fallbackDetail;
    }
  }

  Future<RouteArrivalSnapshot> routeArrival(RouteArrivalRequest request) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tracking/routes/${request.routeId}/arrival',
        queryParameters: {
          'lat': request.lat,
          'lng': request.lng,
          if (request.pickupStopId != null)
            'pickupStopId': request.pickupStopId,
        },
      );
      return RouteArrivalSnapshot.fromJson(response.data ?? const {});
    } catch (_) {
      return RouteArrivalSnapshot.fallback();
    }
  }

  Future<PassengerWaitSession?> startPassengerWait({
    required String routeId,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/tracking/routes/$routeId/passenger-waits',
        data: {
          'anonymousSessionId': await _anonymousSessionId(),
          'lat': lat,
          'lng': lng,
        },
      );
      return PassengerWaitSession.fromJson(response.data ?? const {});
    } catch (_) {
      return null;
    }
  }

  Future<PassengerWaitSession?> updatePassengerWait({
    required String waitId,
    required double lat,
    required double lng,
    double? accuracyMeters,
    double? speedMetersPerSecond,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/tracking/passenger-waits/$waitId/location',
        data: {
          'lat': lat,
          'lng': lng,
          if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
          if (speedMetersPerSecond != null)
            'speedMetersPerSecond': speedMetersPerSecond,
        },
      );
      return PassengerWaitSession.fromJson(response.data ?? const {});
    } catch (_) {
      return null;
    }
  }

  Future<PassengerWaitSession?> cancelPassengerWait(String waitId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/tracking/passenger-waits/$waitId/cancel',
      );
      return PassengerWaitSession.fromJson(response.data ?? const {});
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadActiveWaitRouteId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_wait_route_id');
  }

  Future<String?> loadActiveWaitSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_wait_session_id');
  }

  Future<void> saveActiveWaitRouteId(String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_wait_route_id', routeId);
  }

  Future<void> saveActiveWaitSessionId(String waitId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_wait_session_id', waitId);
  }

  Future<void> clearActiveWaitRouteId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_wait_route_id');
    await prefs.remove('active_wait_session_id');
  }

  Future<Set<String>> loadSavedRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('saved_route_ids') ?? const []).toSet();
  }

  Future<bool> isRouteSaved(String routeId) async {
    return (await loadSavedRouteIds()).contains(routeId);
  }

  Future<void> setRouteSaved(String routeId, bool saved) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList('saved_route_ids') ?? const []).toSet();
    if (saved) {
      ids.add(routeId);
    } else {
      ids.remove(routeId);
    }
    await prefs.setStringList('saved_route_ids', ids.toList()..sort());
  }

  Future<String> _anonymousSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('anonymous_session_id');
    if (existing != null) return existing;
    final generated = 'passenger-${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString('anonymous_session_id', generated);
    return generated;
  }
}

class PassengerWaitSession {
  const PassengerWaitSession({required this.id, required this.status});

  final String id;
  final String status;

  bool get isBoarded => status == 'boarded';

  factory PassengerWaitSession.fromJson(Map<String, dynamic> json) {
    return PassengerWaitSession(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'waiting',
    );
  }
}

class RouteArrivalRequest {
  const RouteArrivalRequest({
    required this.routeId,
    required this.lat,
    required this.lng,
    this.pickupStopId,
  });

  final String routeId;
  final double lat;
  final double lng;
  final String? pickupStopId;

  @override
  bool operator ==(Object other) {
    return other is RouteArrivalRequest &&
        other.routeId == routeId &&
        other.lat == lat &&
        other.lng == lng &&
        other.pickupStopId == pickupStopId;
  }

  @override
  int get hashCode => Object.hash(routeId, lat, lng, pickupStopId);

  @override
  String toString() => '$routeId:$lat:$lng:$pickupStopId';
}

class RouteArrivalSnapshot {
  const RouteArrivalSnapshot({
    required this.selectedVehicle,
    required this.alternatives,
    required this.skippedPassedVehicles,
  });

  final VehicleArrivalEstimate? selectedVehicle;
  final List<VehicleArrivalEstimate> alternatives;
  final List<VehicleArrivalEstimate> skippedPassedVehicles;

  List<VehicleArrivalEstimate> get vehicles => [
        if (selectedVehicle != null) selectedVehicle!,
        ...alternatives,
        ...skippedPassedVehicles,
      ];

  factory RouteArrivalSnapshot.fromJson(Map<String, dynamic> json) {
    final selected = json['selectedVehicle'] as Map<String, dynamic>?;
    final alternatives = json['alternatives'] as List<dynamic>? ?? const [];
    final skipped = json['skippedPassedVehicles'] as List<dynamic>? ?? const [];
    return RouteArrivalSnapshot(
      selectedVehicle:
          selected == null ? null : VehicleArrivalEstimate.fromJson(selected),
      alternatives: alternatives
          .whereType<Map<String, dynamic>>()
          .map(VehicleArrivalEstimate.fromJson)
          .toList(),
      skippedPassedVehicles: skipped
          .whereType<Map<String, dynamic>>()
          .map(VehicleArrivalEstimate.fromJson)
          .toList(),
    );
  }

  factory RouteArrivalSnapshot.fallback() {
    return RouteArrivalSnapshot(
      selectedVehicle: sampleVehicles[0],
      alternatives: const [],
      skippedPassedVehicles: [sampleVehicles[1]],
    );
  }
}

const _fallbackRoutes = [
  sampleRoute,
  TransitRoute(
    id: 'mansour',
    nameAr: 'الباب الشرقي - المنصور',
    routeType: RouteType.kia,
    status: RouteStatus.active,
    fareMin: 500,
    fareMax: 1000,
    operatingHoursStart: '٦:٣٠ ص',
    operatingHoursEnd: '١١:٠٠ م',
    confidenceScore: 82,
    lastVerifiedAt: null,
  ),
];

const _fallbackDetail =
    TransitRouteDetail(route: sampleRoute, stops: sampleStops);
