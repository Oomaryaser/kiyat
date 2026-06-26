import 'dart:convert';

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
  final routes = await repository.listRoutes(limit: 40);
  final activeRouteId = await repository.loadActiveWaitRouteId();
  final savedRouteIds = await repository.loadSavedRouteIds();
  final priorityIds = <String>{
    if (activeRouteId != null) activeRouteId,
    ...savedRouteIds,
    ...routes.take(8).map((route) => route.id),
  };
  final details = await repository.routeDetails(priorityIds.toList());
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
  TransitRepository(this._dio);

  final Dio _dio;
  final Map<String, TransitRouteDetail> _detailMemoryCache = {};
  List<TransitRoute>? _routesMemoryCache;
  DateTime? _routesMemoryCachedAt;

  static const _routesCacheKey = 'cache_routes_v1';
  static const _routesCacheSavedAtKey = 'cache_routes_v1_saved_at';
  static const _routeDetailCachePrefix = 'cache_route_detail_v1_';
  static const _routeDetailSavedAtPrefix = 'cache_route_detail_v1_saved_at_';
  static const _freshCacheTtl = Duration(minutes: 5);
  static const _staleCacheTtl = Duration(days: 7);

  Future<List<TransitRoute>> listRoutes(
      {int limit = 40, bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _routesMemoryCache != null &&
        _routesMemoryCachedAt != null &&
        now.difference(_routesMemoryCachedAt!) < _freshCacheTtl) {
      return _routesMemoryCache!;
    }

    if (!forceRefresh) {
      final cached = await _loadCachedRoutes(maxAge: _freshCacheTtl);
      if (cached.isNotEmpty) {
        _routesMemoryCache = cached;
        _routesMemoryCachedAt = now;
        return cached;
      }
    }

    try {
      final response = await _retry(
        () => _dio.get<Map<String, dynamic>>(
          '/routes',
          queryParameters: {'limit': limit},
        ),
      );
      final raw = response.data ?? const <String, dynamic>{};
      final data = raw['data'] as List<dynamic>? ?? const [];
      final routes = data
          .whereType<Map<String, dynamic>>()
          .map(TransitRoute.fromJson)
          .toList();
      if (routes.isEmpty) {
        throw Exception('No routes found');
      }
      await _saveRoutesCache(raw);
      _routesMemoryCache = routes;
      _routesMemoryCachedAt = now;
      return routes;
    } catch (_) {
      final cached = await _loadCachedRoutes(maxAge: _staleCacheTtl);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<TransitRouteDetail> routeDetail(String routeId,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _detailMemoryCache.containsKey(routeId)) {
      return _detailMemoryCache[routeId]!;
    }

    if (!forceRefresh) {
      final cached =
          await _loadCachedRouteDetail(routeId, maxAge: _freshCacheTtl);
      if (cached != null) {
        _detailMemoryCache[routeId] = cached;
        return cached;
      }
    }

    try {
      final response = await _retry(
        () => _dio.get<Map<String, dynamic>>('/routes/$routeId'),
      );
      final raw = response.data ?? const <String, dynamic>{};
      final detail = TransitRouteDetail.fromJson(raw);
      if (detail.stops.isEmpty) {
        throw Exception('Route has no path anchors');
      }
      await _saveRouteDetailCache(routeId, raw);
      _detailMemoryCache[routeId] = detail;
      return detail;
    } catch (_) {
      final cached =
          await _loadCachedRouteDetail(routeId, maxAge: _staleCacheTtl);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<TransitRouteDetail>> routeDetails(List<String> routeIds) async {
    final details = <TransitRouteDetail>[];
    const batchSize = 3;
    for (var index = 0; index < routeIds.length; index += batchSize) {
      final batch = routeIds.skip(index).take(batchSize);
      final batchResults = await Future.wait(
        batch.map((id) async {
          try {
            return await routeDetail(id);
          } catch (_) {
            return null;
          }
        }),
      );
      details.addAll(batchResults.whereType<TransitRouteDetail>());
    }
    return details;
  }

  Future<RouteArrivalSnapshot> routeArrival(RouteArrivalRequest request) async {
    try {
      final response = await _retry(
        () => _dio.get<Map<String, dynamic>>(
          '/tracking/routes/${request.routeId}/arrival',
          queryParameters: {
            'lat': request.lat,
            'lng': request.lng,
            if (request.pickupStopId != null)
              'pickupStopId': request.pickupStopId,
          },
        ),
      );
      return RouteArrivalSnapshot.fromJson(response.data ?? const {});
    } catch (_) {
      rethrow;
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
        options: Options(
          headers: {
            'X-Anonymous-Session-Id': await _anonymousSessionId(),
          },
        ),
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
        options: Options(
          headers: {
            'X-Anonymous-Session-Id': await _anonymousSessionId(),
          },
        ),
      );
      return PassengerWaitSession.fromJson(response.data ?? const {});
    } catch (_) {
      return null;
    }
  }

  Future<PassengerWaitSession?> boardPassengerWait(String waitId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/tracking/passenger-waits/$waitId/board',
        options: Options(
          headers: {
            'X-Anonymous-Session-Id': await _anonymousSessionId(),
          },
        ),
      );
      return PassengerWaitSession.fromJson(response.data ?? const {});
    } catch (_) {
      return null;
    }
  }

  Future<bool> submitReport({
    required String routeId,
    required String reportType,
    required String description,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>('/reports', data: {
        'routeId': routeId,
        'reportType': reportType,
        'description': description,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitTripRating({
    required String routeId,
    String? passengerWaitId,
    required int rating,
    String? crowdingLevel,
    bool? priceFair,
    int? cleanlinessRating,
    String? comment,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>('/trip-ratings', data: {
        'routeId': routeId,
        if (passengerWaitId != null) 'passengerWaitId': passengerWaitId,
        'rating': rating,
        if (crowdingLevel != null) 'crowdingLevel': crowdingLevel,
        if (priceFair != null) 'priceFair': priceFair,
        if (cleanlinessRating != null) 'cleanlinessRating': cleanlinessRating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      });
      return true;
    } catch (_) {
      return false;
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

  Future<void> clearRouteCaches() async {
    final prefs = await SharedPreferences.getInstance();
    _routesMemoryCache = null;
    _routesMemoryCachedAt = null;
    _detailMemoryCache.clear();
    final keys = prefs.getKeys().where(
          (key) =>
              key == _routesCacheKey ||
              key == _routesCacheSavedAtKey ||
              key.startsWith(_routeDetailCachePrefix) ||
              key.startsWith(_routeDetailSavedAtPrefix),
        );
    for (final key in keys.toList()) {
      await prefs.remove(key);
    }
  }

  Future<String> _anonymousSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('anonymous_session_id');
    if (existing != null) return existing;
    final generated = 'passenger-${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString('anonymous_session_id', generated);
    return generated;
  }

  Future<Response<T>> _retry<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      final canRetry =
          status == 0 || status == 408 || status == 429 || status >= 500;
      if (!canRetry) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return request();
    }
  }

  Future<void> _saveRoutesCache(Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _routesCacheSavedAtKey, DateTime.now().toIso8601String());
    await prefs.setString(_routesCacheKey, _encodeJson(raw));
  }

  Future<List<TransitRoute>> _loadCachedRoutes(
      {required Duration maxAge}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedAt =
        DateTime.tryParse(prefs.getString(_routesCacheSavedAtKey) ?? '');
    final raw = prefs.getString(_routesCacheKey);
    if (savedAt == null ||
        raw == null ||
        DateTime.now().difference(savedAt) > maxAge) {
      return const [];
    }
    final json = _decodeJson(raw);
    final data = json?['data'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(TransitRoute.fromJson)
        .where((route) => route.id.isNotEmpty)
        .toList();
  }

  Future<void> _saveRouteDetailCache(
      String routeId, Map<String, dynamic> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_routeDetailCachePrefix$routeId', _encodeJson(raw));
    await prefs.setString(
      '$_routeDetailSavedAtPrefix$routeId',
      DateTime.now().toIso8601String(),
    );
  }

  Future<TransitRouteDetail?> _loadCachedRouteDetail(
    String routeId, {
    required Duration maxAge,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedAt = DateTime.tryParse(
      prefs.getString('$_routeDetailSavedAtPrefix$routeId') ?? '',
    );
    final raw = prefs.getString('$_routeDetailCachePrefix$routeId');
    if (savedAt == null ||
        raw == null ||
        DateTime.now().difference(savedAt) > maxAge) {
      return null;
    }
    final json = _decodeJson(raw);
    if (json == null) return null;
    final detail = TransitRouteDetail.fromJson(json);
    return detail.stops.isEmpty ? null : detail;
  }

  String _encodeJson(Map<String, dynamic> value) => jsonEncode(value);

  Map<String, dynamic>? _decodeJson(String value) {
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
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

  int get _latBucket => (lat * 100000).round();
  int get _lngBucket => (lng * 100000).round();

  @override
  bool operator ==(Object other) {
    return other is RouteArrivalRequest &&
        other.routeId == routeId &&
        other._latBucket == _latBucket &&
        other._lngBucket == _lngBucket &&
        other.pickupStopId == pickupStopId;
  }

  @override
  int get hashCode =>
      Object.hash(routeId, _latBucket, _lngBucket, pickupStopId);

  @override
  String toString() => '$routeId:$_latBucket:$_lngBucket:$pickupStopId';
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
}
