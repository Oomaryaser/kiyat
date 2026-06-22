import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/utils/location_helper.dart';

import '../../shared/data/transit_repository.dart';
import '../../shared/models/transit_models.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? activeRouteId;
  String searchQuery = '';
  Position? currentPosition;
  String? locationMessage;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _waitHeartbeatTimer;
  String? _waitSessionId;
  String? _waitStatus;
  double? _pickupLat;
  double? _pickupLng;
  double? _userLat;
  double? _userLng;
  bool ratingPromptShown = false;
  DateTime? _waitLastSyncedAt;
  String? _waitSyncError;

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _waitHeartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(routeDetailsProvider);
    final savedActiveRouteId = ref.watch(activeWaitRouteIdProvider).maybeWhen(
          data: (routeId) => routeId,
          orElse: () => null,
        );

    if (savedActiveRouteId != null && _positionSubscription == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startTrackingForRoute(savedActiveRouteId);
        }
      });
    } else if (savedActiveRouteId == null && _positionSubscription != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _stopWaitTracking();
        }
      });
    }

    return Scaffold(
      extendBody: true,
      body: detailsAsync.when(
        data: (details) {
          final activeId = _effectiveActiveRouteId(
            details.map((detail) => detail.route).toList(),
            savedActiveRouteId,
          );
          return _PassengerHomeDashboard(
            details: details,
            activeRouteId: activeId,
            searchQuery: searchQuery,
            currentPosition: currentPosition,
            locationMessage: locationMessage,
            onSearchChanged: (value) => setState(() => searchQuery = value),
            onUseCurrentLocation: _loadCurrentPosition,
            onRefresh: _refreshHome,
            onStopWaiting: _cancelWait,
            pickupLat: _pickupLat,
            pickupLng: _pickupLng,
            userLat: _userLat,
            userLng: _userLng,
            syncError: _waitSyncError,
            lastSyncedAt: _waitLastSyncedAt,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _PassengerHomeDashboard(
          details: const [],
          activeRouteId: null,
          searchQuery: searchQuery,
          currentPosition: currentPosition,
          locationMessage: 'ما قدرنا نتصل بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
          onSearchChanged: (value) => setState(() => searchQuery = value),
          onUseCurrentLocation: _loadCurrentPosition,
          onRefresh: _refreshHome,
          onStopWaiting: _cancelWait,
          pickupLat: _pickupLat,
          pickupLng: _pickupLng,
          userLat: _userLat,
          userLng: _userLng,
          syncError: _waitSyncError,
          lastSyncedAt: _waitLastSyncedAt,
        ),
      ),
    );
  }

  String? _effectiveActiveRouteId(
      List<TransitRoute> routes, String? savedRouteId) {
    if (routes.isEmpty) return null;
    if (activeRouteId != null &&
        routes.any((route) => route.id == activeRouteId)) {
      return activeRouteId;
    }
    if (savedRouteId != null &&
        routes.any((route) => route.id == savedRouteId)) {
      return savedRouteId;
    }
    return null;
  }

  Future<void> _refreshHome() async {
    ref.invalidate(routeDetailsProvider);
    ref.invalidate(activeWaitRouteIdProvider);
    await _loadCurrentPosition();
  }

  Future<void> _cancelWait() async {
    final repository = ref.read(transitRepositoryProvider);
    final waitId = await repository.loadActiveWaitSessionId();
    if (waitId != null && waitId.isNotEmpty) {
      await repository.cancelPassengerWait(waitId);
    }
    _stopWaitTracking();
    await repository.clearActiveWaitRouteId();
    ref.invalidate(activeWaitRouteIdProvider);
    if (!mounted) return;
    setState(() {
      activeRouteId = null;
    });
  }

  Future<void> _startTrackingForRoute(String routeId) async {
    final repository = ref.read(transitRepositoryProvider);
    final waitId = await repository.loadActiveWaitSessionId();
    if (waitId == null || waitId.isEmpty) return;

    setState(() {
      _waitSessionId = waitId;
      _waitStatus = 'waiting';
      _waitSyncError = null;
    });

    try {
      final detail = await repository.routeDetail(routeId);
      final stops = detail.stops;
      final position = await KiyatLocation.getCurrentPosition();
      final nearestOnLine = _findNearestPointOnRouteLine(
        LatLng(position.latitude, position.longitude),
        stops,
      );

      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
        _pickupLat = nearestOnLine.latitude;
        _pickupLng = nearestOnLine.longitude;
      });

      _startLocationStream(stops, routeId);
      _startWaitHeartbeat();
    } catch (_) {}
  }

  void _startLocationStream(List<TransitStop> stops, String routeId) {
    final waitId = _waitSessionId;
    if (waitId == null || waitId.isEmpty) return;
    _positionSubscription?.cancel();
    _positionSubscription = KiyatLocation.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) async {
      final repository = ref.read(transitRepositoryProvider);
      final session = await repository.updatePassengerWait(
        waitId: waitId,
        lat: position.latitude,
        lng: position.longitude,
        accuracyMeters: position.accuracy,
        speedMetersPerSecond:
            position.speed.isFinite && position.speed >= 0
                ? position.speed
                : null,
      );
      if (!mounted) return;
      if (session == null) {
        setState(() {
          _waitSyncError =
              'تحديث موقعك ما وصل للسائق. راح نعيد المحاولة تلقائياً.';
        });
        return;
      }

      LatLng nextPickup = _findNearestPointOnRouteLine(
        LatLng(position.latitude, position.longitude),
        stops,
      );

      setState(() {
        _waitStatus = session.status;
        _waitLastSyncedAt = DateTime.now();
        _waitSyncError = null;
        _userLat = position.latitude;
        _userLng = position.longitude;
        _pickupLat = nextPickup.latitude;
        _pickupLng = nextPickup.longitude;
      });

      if (session.isBoarded) {
        _stopWaitTracking();
        await repository.clearActiveWaitRouteId();
        ref.invalidate(activeWaitRouteIdProvider);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اعتبرناك صعدت الكية، شلنا نقطة انتظارك.'),
          ),
        );
        _showTripRatingSheet(routeId, waitId);
      }
    });
  }

  void _startWaitHeartbeat() {
    _waitHeartbeatTimer?.cancel();
    _waitHeartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final waitId = _waitSessionId;
      final nextLat = _userLat ?? _pickupLat;
      final nextLng = _userLng ?? _pickupLng;
      if (waitId == null ||
          waitId.isEmpty ||
          _waitStatus != 'waiting' ||
          nextLat == null ||
          nextLng == null) {
        return;
      }
      ref
          .read(transitRepositoryProvider)
          .updatePassengerWait(
            waitId: waitId,
            lat: nextLat,
            lng: nextLng,
          )
          .then((session) {
        if (!mounted) return;
        if (session == null) {
          setState(() {
            _waitSyncError =
                'تحديث ظهورك للسائق تأخر. راح نعيد المحاولة تلقائياً.';
          });
          return;
        }
        setState(() {
          _waitStatus = session.status;
          _waitLastSyncedAt = DateTime.now();
          _waitSyncError = null;
        });
      });
    });
  }

  void _stopWaitTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _waitHeartbeatTimer?.cancel();
    _waitHeartbeatTimer = null;
    setState(() {
      _waitSessionId = null;
      _waitStatus = null;
      _waitLastSyncedAt = null;
      _waitSyncError = null;
      _pickupLat = null;
      _pickupLng = null;
      _userLat = null;
      _userLng = null;
    });
  }

  LatLng _findNearestPointOnRouteLine(LatLng point, List<TransitStop> stops) {
    if (stops.isEmpty) return point;
    LatLng nearestPoint = LatLng(stops.first.lat, stops.first.lng);
    double minDistance = double.infinity;

    for (int i = 0; i < stops.length - 1; i++) {
      LatLng p1 = LatLng(stops[i].lat, stops[i].lng);
      LatLng p2 = LatLng(stops[i + 1].lat, stops[i + 1].lng);
      LatLng projected = _projectPointToSegment(point, p1, p2);
      double dist = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        projected.latitude,
        projected.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestPoint = projected;
      }
    }
    return nearestPoint;
  }

  LatLng _projectPointToSegment(LatLng p, LatLng p1, LatLng p2) {
    double x = p.longitude;
    double y = p.latitude;
    double x1 = p1.longitude;
    double y1 = p1.latitude;
    double x2 = p2.longitude;
    double y2 = p2.latitude;

    double dx = x2 - x1;
    double dy = y2 - y1;
    double lenSq = dx * dx + dy * dy;

    double t = lenSq == 0 ? 0 : ((x - x1) * dx + (y - y1) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);

    return LatLng(y1 + dy * t, x1 + dx * t);
  }

  void _showTripRatingSheet(String routeId, String waitId) {
    if (ratingPromptShown) return;
    ratingPromptShown = true;
    var rating = 5;
    var cleanliness = 5;
    var crowding = 'medium';
    var priceFair = true;
    final commentController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              final success = await ref.read(transitRepositoryProvider).submitTripRating(
                    routeId: routeId,
                    passengerWaitId: waitId,
                    rating: rating,
                    crowdingLevel: crowding,
                    priceFair: priceFair,
                    cleanlinessRating: cleanliness,
                    comment: commentController.text,
                  );
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'شكراً، سجلنا تقييمك للرحلة.'
                        : 'ما قدرنا نسجل التقييم حالياً.',
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('كيف كانت الكية؟', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _RatingStars(
                    value: rating,
                    onChanged: (value) => setSheetState(() => rating = value),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'low', label: Text('خفيف')),
                      ButtonSegment(value: 'medium', label: Text('متوسط')),
                      ButtonSegment(value: 'high', label: Text('مزدحم')),
                    ],
                    selected: {crowding},
                    onSelectionChanged: (value) {
                      setSheetState(() => crowding = value.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('السعر كان مناسب'),
                    value: priceFair,
                    onChanged: (value) => setSheetState(() => priceFair = value),
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('النظافة')),
                      _RatingStars(
                        value: cleanliness,
                        compact: true,
                        onChanged: (value) => setSheetState(() => cleanliness = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'ملاحظة اختيارية',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: submit,
                    child: const Text('إرسال التقييم'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      commentController.dispose();
      ratingPromptShown = false;
    });
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        setState(() =>
            locationMessage = 'خدمة الموقع مطفية، الخطوط مرتبة بدون قربك.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() =>
            locationMessage = 'فعل صلاحية الموقع حتى نرتب الخطوط حسب قربها.');
        return;
      }
      final position = await KiyatLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!mounted) return;
      setState(() {
        currentPosition = position;
        locationMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => locationMessage = 'ما قدرنا نحدث موقعك حالياً.');
    }
  }
}

class _PassengerHomeDashboard extends ConsumerWidget {
  const _PassengerHomeDashboard({
    required this.details,
    required this.activeRouteId,
    required this.searchQuery,
    required this.currentPosition,
    required this.locationMessage,
    required this.onSearchChanged,
    required this.onUseCurrentLocation,
    required this.onRefresh,
    required this.onStopWaiting,
    this.pickupLat,
    this.pickupLng,
    this.userLat,
    this.userLng,
    this.syncError,
    this.lastSyncedAt,
  });

  final List<TransitRouteDetail> details;
  final String? activeRouteId;
  final String searchQuery;
  final Position? currentPosition;
  final String? locationMessage;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onUseCurrentLocation;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onStopWaiting;
  final double? pickupLat;
  final double? pickupLng;
  final double? userLat;
  final double? userLng;
  final String? syncError;
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeDetail = activeRouteId == null
        ? null
        : details
            .where((detail) => detail.route.id == activeRouteId)
            .firstOrNull;
    if (activeDetail != null) {
      final pickup = _pickupAnchor(activeDetail);
      final activePosition = userLat != null && userLng != null
          ? Position(
              latitude: userLat!,
              longitude: userLng!,
              timestamp: DateTime.now(),
              accuracy: 10.0,
              altitude: 0.0,
              altitudeAccuracy: 0.0,
              heading: 0.0,
              headingAccuracy: 0.0,
              speed: 0.0,
              speedAccuracy: 0.0,
            )
          : currentPosition;
      final request = RouteArrivalRequest(
        routeId: activeDetail.route.id,
        lat: pickupLat ?? currentPosition?.latitude ?? pickup.latitude,
        lng: pickupLng ?? currentPosition?.longitude ?? pickup.longitude,
        pickupStopId: currentPosition == null && activeDetail.stops.isNotEmpty
            ? activeDetail.stops.first.id
            : null,
      );
      final arrivalAsync = ref.watch(routeArrivalProvider(request));
      return _ActiveWaitingHome(
        detail: activeDetail,
        currentPosition: activePosition,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        arrivalAsync: arrivalAsync,
        onUseCurrentLocation: onUseCurrentLocation,
        onOpenLiveMap: () => context.push('/routes/${activeDetail.route.id}'),
        onStopWaiting: onStopWaiting,
        syncError: syncError,
        lastSyncedAt: lastSyncedAt,
      );
    }

    final sorted = _sortedAndFilteredDetails;
    final visibleDetails = sorted.take(4).toList();

    return Stack(
      children: [
        Positioned.fill(
          child: _PassengerHomeMap(
            details: details.take(4).toList(),
            currentPosition: currentPosition,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _NotificationButton(onTap: () => context.push('/settings')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HomeSearchPill(
                        value: searchQuery,
                        onChanged: onSearchChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _CurrentLocationChip(
                    hasLocation: currentPosition != null,
                    message: locationMessage,
                    onTap: onUseCurrentLocation,
                  ),
                ),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          end: 28,
          bottom: 210,
          child: _MapLocateButton(onTap: onUseCurrentLocation),
        ),
        _NearbyRoutesSheet(
          details: visibleDetails,
          activeRouteId: activeRouteId,
          currentPosition: currentPosition,
          locationMessage: locationMessage,
          onRefresh: onRefresh,
        ),
      ],
    );
  }

  List<TransitRouteDetail> get _sortedAndFilteredDetails {
    final query = searchQuery.trim();
    final filtered = query.isEmpty
        ? details
        : details.where((detail) {
            final route = detail.route.nameAr;
            final stops = detail.stops
                .map((stop) => '${stop.nameAr} ${stop.landmarkAr}')
                .join(' ');
            return route.contains(query) || stops.contains(query);
          }).toList();
    final sorted = [...filtered];
    sorted.sort((a, b) {
      final aDistance = _distanceToRoute(a) ?? double.infinity;
      final bDistance = _distanceToRoute(b) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    return sorted;
  }

  double? _distanceToRoute(TransitRouteDetail detail) {
    final position = currentPosition;
    if (position == null || detail.stops.isEmpty) return null;
    return detail.stops
        .map((stop) => Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              stop.lat,
              stop.lng,
            ))
        .reduce((a, b) => a < b ? a : b);
  }

  LatLng _pickupAnchor(TransitRouteDetail detail) {
    if (detail.stops.isEmpty) return const LatLng(33.3152, 44.4161);
    return LatLng(detail.stops.first.lat, detail.stops.first.lng);
  }
}

class _ActiveWaitingHome extends StatelessWidget {
  const _ActiveWaitingHome({
    required this.detail,
    required this.currentPosition,
    this.pickupLat,
    this.pickupLng,
    required this.arrivalAsync,
    required this.onUseCurrentLocation,
    required this.onOpenLiveMap,
    required this.onStopWaiting,
    this.syncError,
    this.lastSyncedAt,
  });

  final TransitRouteDetail detail;
  final Position? currentPosition;
  final double? pickupLat;
  final double? pickupLng;
  final AsyncValue<RouteArrivalSnapshot> arrivalAsync;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onOpenLiveMap;
  final Future<void> Function() onStopWaiting;
  final String? syncError;
  final DateTime? lastSyncedAt;

  int _pickupDistanceMeters() {
    final position = currentPosition;
    if (position == null || detail.stops.isEmpty) return 50;
    final lat = pickupLat ?? detail.stops.first.lat;
    final lng = pickupLng ?? detail.stops.first.lng;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lng,
    ).round().clamp(35, 850);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = arrivalAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const RouteArrivalSnapshot(
        selectedVehicle: null,
        alternatives: [],
        skippedPassedVehicles: [],
      ),
    );
    final vehicles = snapshot.vehicles;
    final selectedVehicle = snapshot.selectedVehicle ?? vehicles.firstOrNull;
    final etaMinutes = selectedVehicle?.etaMinutes ?? 3;
    const confidence = 92;

    final pickupDistance = _pickupDistanceMeters();
    final walkingMinutes = (pickupDistance / 70).clamp(1, 8).ceil();
    final showWalkingNavigation = pickupDistance > 30 && currentPosition != null;

    return Stack(
      children: [
        Positioned.fill(
          child: _PassengerHomeMap(
            details: [detail],
            currentPosition: currentPosition,
            vehicles: vehicles,
            isWaitingMode: true,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              children: [
                if (showWalkingNavigation) ...[
                  _WalkingNavigationBanner(
                    stopName: detail.stops.isNotEmpty ? detail.stops.first.nameAr : 'الموقف الأول',
                    distanceMeters: pickupDistance,
                    walkingMinutes: walkingMinutes,
                  ),
                  const SizedBox(height: 10),
                ],
                _WaitingHeroCard(
                  routeName: _routeDisplayName(detail),
                  etaMinutes: etaMinutes,
                  confidence: confidence,
                  isLoading: arrivalAsync.isLoading,
                  syncError: syncError,
                  lastSyncedAt: lastSyncedAt,
                ),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          end: 18,
          bottom: 176,
          child: _MapLocateButton(onTap: onUseCurrentLocation),
        ),
        _WaitingOperationsSheet(
          detail: detail,
          currentPosition: currentPosition,
          onStopWaiting: onStopWaiting,
        ),
      ],
    );
  }

  String _routeDisplayName(TransitRouteDetail detail) {
    final parts = detail.route.nameAr.split(RegExp(r'\s*[-–—]\s*'));
    if (parts.length > 1) return '${parts.first} ← ${parts.last}';
    if (detail.stops.length > 1) {
      return '${detail.stops.first.nameAr} ← ${detail.stops.last.nameAr}';
    }
    return detail.route.nameAr;
  }
}

class _WalkingNavigationBanner extends StatelessWidget {
  const _WalkingNavigationBanner({
    required this.stopName,
    required this.distanceMeters,
    required this.walkingMinutes,
  });

  final String stopName;
  final int distanceMeters;
  final int walkingMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F5132), // Google Maps dark green
            Color(0xFF14532D), // slightly darker forest green
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F5132).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.directions_walk_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اتجه سيراً نحو موقف الصعود: $stopName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '$distanceMeters متر · $walkingMinutes دقيقة مشياً',
                        style: const TextStyle(
                          color: Color(0xFFD1FAE5),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFD1FAE5),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'اتبع المسار الأخضر المنقط',
                        style: TextStyle(
                          color: Color(0xFFD1FAE5),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingHeroCard extends StatelessWidget {
  const _WaitingHeroCard({
    required this.routeName,
    required this.etaMinutes,
    required this.confidence,
    required this.isLoading,
    this.syncError,
    this.lastSyncedAt,
  });

  final String routeName;
  final int etaMinutes;
  final int confidence;
  final bool isLoading;
  final String? syncError;
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E8B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: Color(0xFF1B5E8B),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          routeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF071827),
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Tajawal',
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isLoading ? 'نحدث حركة الخط الآن' : 'أنت تنتظر الآن',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '$etaMinutes',
                    style: const TextStyle(
                      color: Color(0xFF071827),
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 0.9,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'دقائق لأقرب كية',
                    style: TextStyle(
                      color: Color(0xFF173244),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                ],
              ),
              if (syncError != null || lastSyncedAt != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0x1F000000)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      syncError != null
                          ? Icons.sync_problem_rounded
                          : Icons.sync_lock_rounded,
                      size: 14,
                      color: syncError != null
                          ? const Color(0xFFC0392B)
                          : const Color(0xFF27AE60),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        syncError ?? 'تمت مشاركة موقعك مع السائق بنجاح',
                        style: TextStyle(
                          color: syncError != null
                              ? const Color(0xFFC0392B)
                              : Colors.grey.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingOperationsSheet extends StatelessWidget {
  const _WaitingOperationsSheet({
    required this.detail,
    required this.currentPosition,
    required this.onStopWaiting,
  });

  final TransitRouteDetail detail;
  final Position? currentPosition;
  final Future<void> Function() onStopWaiting;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: _GlassSurface(
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'تتبع حركة الخط نشط وموقعك مرسل للسائقين',
                      style: TextStyle(
                        color: Color(0xFF173244),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: onStopWaiting,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: BorderSide(
                      color: const Color(0xFFB42318).withValues(alpha: 0.18),
                    ),
                    backgroundColor: const Color(0xFFFFF1F0).withValues(alpha: 0.72),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                  child: const Text('إيقاف الانتظار'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PassengerHomeMap extends StatefulWidget {
  const _PassengerHomeMap({
    required this.details,
    required this.currentPosition,
    this.vehicles = const [],
    this.isWaitingMode = false,
    this.pickupLat,
    this.pickupLng,
  });

  final List<TransitRouteDetail> details;
  final Position? currentPosition;
  final List<VehicleArrivalEstimate> vehicles;
  final bool isWaitingMode;
  final double? pickupLat;
  final double? pickupLng;

  @override
  State<_PassengerHomeMap> createState() => _PassengerHomeMapState();
}

class _PassengerHomeMapState extends State<_PassengerHomeMap> {
  final Map<String, List<LatLng>> _roadPaths = {};
  List<LatLng> _walkingPath = [];
  GoogleMapController? _mapController;
  bool _navigationModeActive = true;
  bool _mapInitialized = false;

  static const _mapStyle = '''
[
  {
    "featureType": "poi",
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  }
]
''';

  @override
  void initState() {
    super.initState();
    _loadRoadPaths();
    _loadWalkingPath();
  }

  @override
  void didUpdateWidget(covariant _PassengerHomeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.details.map((detail) => detail.route.id).join(',');
    final nextIds = widget.details.map((detail) => detail.route.id).join(',');
    if (oldIds != nextIds) _loadRoadPaths();

    final oldUser = oldWidget.currentPosition;
    final nextUser = widget.currentPosition;
    final userMoved = oldUser?.latitude != nextUser?.latitude || oldUser?.longitude != nextUser?.longitude;

    if (widget.isWaitingMode != oldWidget.isWaitingMode || userMoved || oldIds != nextIds) {
      _loadWalkingPath();
    }
  }

  Future<void> _loadWalkingPath() async {
    if (!widget.isWaitingMode ||
        widget.currentPosition == null ||
        widget.details.isEmpty ||
        widget.details.first.stops.isEmpty) {
      if (_walkingPath.isNotEmpty) {
        setState(() {
          _walkingPath = [];
        });
      }
      return;
    }

    final userLat = widget.currentPosition!.latitude;
    final userLng = widget.currentPosition!.longitude;
    final stopLat = widget.pickupLat ?? widget.details.first.stops.first.lat;
    final stopLng = widget.pickupLng ?? widget.details.first.stops.first.lng;

    final distance = Geolocator.distanceBetween(userLat, userLng, stopLat, stopLng);
    if (distance <= 30) {
      if (_walkingPath.isNotEmpty) {
        setState(() {
          _walkingPath = [];
        });
      }
      return;
    }

    try {
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/foot/$userLng,$userLat;$stopLng,$stopLat',
        {'overview': 'full', 'geometries': 'geojson'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>? ?? const [];
        final geometry = routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List<dynamic>? ?? const [];
        final points = coordinates
            .whereType<List<dynamic>>()
            .where((point) => point.length >= 2)
            .map((point) => LatLng(
                  (point[1] as num).toDouble(),
                  (point[0] as num).toDouble(),
                ))
            .toList();

        if (mounted) {
          setState(() {
            _walkingPath = points;
          });
          _animateCameraToNavigation();
        }
      } else {
        if (mounted) {
          setState(() {
            _walkingPath = [LatLng(userLat, userLng), LatLng(stopLat, stopLng)];
          });
          _animateCameraToNavigation();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _walkingPath = [LatLng(userLat, userLng), LatLng(stopLat, stopLng)];
        });
        _animateCameraToNavigation();
      }
    }
  }

  void _animateCameraToNavigation() {
    if (_mapController == null ||
        widget.currentPosition == null ||
        widget.details.isEmpty ||
        widget.details.first.stops.isEmpty) {
      return;
    }
    if (!_navigationModeActive) {
      return;
    }

    final userLat = widget.currentPosition!.latitude;
    final userLng = widget.currentPosition!.longitude;
    final stopLat = widget.pickupLat ?? widget.details.first.stops.first.lat;
    final stopLng = widget.pickupLng ?? widget.details.first.stops.first.lng;

    double bearing = Geolocator.bearingBetween(userLat, userLng, stopLat, stopLng);

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(userLat, userLng),
          zoom: 17.5,
          bearing: bearing,
          tilt: 45.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallbackCenter =
        widget.details.expand((detail) => detail.stops).isEmpty
            ? const LatLng(33.3152, 44.4161)
            : LatLng(widget.pickupLat ?? widget.details.first.stops.first.lat,
                widget.pickupLng ?? widget.details.first.stops.first.lng);
    final center = widget.currentPosition == null
        ? fallbackCenter
        : LatLng(widget.currentPosition!.latitude,
            widget.currentPosition!.longitude);
    final colors = widget.isWaitingMode
        ? [const Color(0xFF1B5E8B)]
        : [
            const Color(0xFF0B78E3),
            const Color(0xFF7B2CBF),
            const Color(0xFFFF8A00),
            const Color(0xFF16A34A),
          ];

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
                target: center, zoom: widget.isWaitingMode ? 13.2 : 12.3),
            style: _mapStyle,
            mapType: MapType.normal,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              if (widget.isWaitingMode && _walkingPath.isNotEmpty) {
                _animateCameraToNavigation();
              }
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted) {
                  _mapInitialized = true;
                }
              });
            },
            onCameraMoveStarted: () {
              if (!_mapInitialized) return;
              if (widget.isWaitingMode && _walkingPath.isNotEmpty && _navigationModeActive) {
                setState(() {
                  _navigationModeActive = false;
                });
              }
            },
            polylines: {
              for (var index = 0; index < widget.details.length; index += 1)
                if (widget.details[index].stops.length > 1)
                  Polyline(
                    polylineId: PolylineId('home_route_$index'),
                    points: _roadPaths[widget.details[index].route.id] ??
                        widget.details[index].stops
                            .map((stop) => LatLng(stop.lat, stop.lng))
                            .toList(),
                    color: colors[index % colors.length],
                    width: widget.isWaitingMode ? 8 : 6,
                    zIndex: 2 + index,
                  ),
              if (widget.isWaitingMode && _walkingPath.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('home_walking_route'),
                  points: _walkingPath,
                  color: const Color(0xFF16A34A),
                  width: 5,
                  patterns: [
                    PatternItem.dash(12),
                    PatternItem.gap(8),
                  ],
                  zIndex: 99,
                ),
            },
            markers: {
              for (var index = 0; index < widget.details.length; index += 1)
                if (widget.details[index].stops.isNotEmpty)
                  Marker(
                    markerId: MarkerId('home_bus_$index'),
                    position: _markerPoint(widget.details[index], index),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      _markerHue(index),
                    ),
                    infoWindow: InfoWindow(title: widget.details[index].route.nameAr),
                  ),
              if (widget.currentPosition != null)
                Marker(
                  markerId: const MarkerId('home_user_location'),
                  position: LatLng(
                    widget.currentPosition!.latitude,
                    widget.currentPosition!.longitude,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                  infoWindow: const InfoWindow(title: 'موقعك'),
                ),
              if (widget.isWaitingMode &&
                  widget.details.isNotEmpty &&
                  widget.details.first.stops.isNotEmpty)
                Marker(
                  markerId: const MarkerId('home_pickup_stop'),
                  position: LatLng(
                    widget.pickupLat ?? widget.details.first.stops.first.lat,
                    widget.pickupLng ?? widget.details.first.stops.first.lng,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueBlue),
                  infoWindow: InfoWindow(
                    title: 'موقف الصعود: ${widget.details.first.stops.first.nameAr}',
                    snippet: widget.details.first.stops.first.landmarkAr,
                  ),
                ),
              for (var index = 0; index < widget.vehicles.length; index += 1)
                if (widget.vehicles[index].lat != 0 &&
                    widget.vehicles[index].lng != 0)
                  Marker(
                    markerId: MarkerId('home_vehicle_$index'),
                    position: LatLng(
                        widget.vehicles[index].lat, widget.vehicles[index].lng),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      index == 0
                          ? BitmapDescriptor.hueOrange
                          : BitmapDescriptor.hueAzure,
                    ),
                    infoWindow: InfoWindow(
                      title: widget.vehicles[index].vehicleLabel,
                      snippet: '${widget.vehicles[index].etaMinutes} دقائق',
                    ),
                  ),
            },
          ),
        ),
        if (widget.isWaitingMode && _walkingPath.isNotEmpty && !_navigationModeActive)
          PositionedDirectional(
            start: 18,
            bottom: 176,
            child: _ReCenterButton(
              onTap: () {
                setState(() {
                  _navigationModeActive = true;
                });
                _animateCameraToNavigation();
              },
            ),
          ),
      ],
    );
  }

  Future<void> _loadRoadPaths() async {
    for (final detail in widget.details) {
      if (detail.stops.length < 2 || _roadPaths.containsKey(detail.route.id)) {
        continue;
      }
      final fallback =
          detail.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList();
      try {
        final coords =
            detail.stops.map((stop) => '${stop.lng},${stop.lat}').join(';');
        final uri = Uri.https(
          'router.project-osrm.org',
          '/route/v1/driving/$coords',
          {'overview': 'full', 'geometries': 'geojson'},
        );
        final response =
            await http.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) {
          if (!mounted) return;
          setState(() => _roadPaths[detail.route.id] = fallback);
          continue;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>? ?? const [];
        final geometry =
            routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
        final coordinates =
            geometry?['coordinates'] as List<dynamic>? ?? const [];
        final points = coordinates
            .whereType<List<dynamic>>()
            .where((point) => point.length >= 2)
            .map((point) => LatLng(
                  (point[1] as num).toDouble(),
                  (point[0] as num).toDouble(),
                ))
            .toList();
        if (!mounted) return;
        setState(() => _roadPaths[detail.route.id] =
            points.length > 1 ? points : fallback);
      } catch (_) {
        if (!mounted) return;
        setState(() => _roadPaths[detail.route.id] = fallback);
      }
    }
  }

  LatLng _markerPoint(TransitRouteDetail detail, int index) {
    final stops = detail.stops;
    final pointIndex =
        stops.length <= 2 ? 0 : (index + 1).clamp(0, stops.length - 1);
    return LatLng(stops[pointIndex].lat, stops[pointIndex].lng);
  }

  double _markerHue(int index) {
    return switch (index % 4) {
      0 => BitmapDescriptor.hueAzure,
      1 => BitmapDescriptor.hueViolet,
      2 => BitmapDescriptor.hueOrange,
      _ => BitmapDescriptor.hueGreen,
    };
  }
}

class _ReCenterButton extends StatelessWidget {
  const _ReCenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF16A34A),
      borderRadius: BorderRadius.circular(999),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.navigation_rounded, size: 20, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'بدء الملاحة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Tajawal',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _RoundMapButton(icon: Icons.notifications_none_rounded, onTap: onTap),
        PositionedDirectional(
          end: 9,
          top: 8,
          child: Container(
            width: 11,
            height: 11,
            decoration: const BoxDecoration(
              color: Color(0xFFFF3B30),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeSearchPill extends StatelessWidget {
  const _HomeSearchPill({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: 32,
      child: SizedBox(
        height: 54,
        child: TextField(
          textAlign: TextAlign.right,
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'إلى أين تريد الذهاب؟',
            hintStyle: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            prefixIcon: value.isEmpty
                ? null
                : IconButton(
                    onPressed: () => onChanged(''),
                    icon: const Icon(Icons.close),
                  ),
            suffixIcon: const Icon(Icons.search_rounded, size: 30),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          ),
        ),
      ),
    );
  }
}

class _CurrentLocationChip extends StatelessWidget {
  const _CurrentLocationChip({
    required this.hasLocation,
    required this.message,
    required this.onTap,
  });

  final bool hasLocation;
  final String? message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: 999,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasLocation ? Icons.my_location : Icons.location_searching,
                size: 17,
                color: const Color(0xFF1B5E8B),
              ),
              const SizedBox(width: 7),
              Text(
                message ?? (hasLocation ? 'موقعك مرئي للنظام' : 'تحديد موقعك'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF173244),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.radius = 32,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MapLocateButton extends StatelessWidget {
  const _MapLocateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 7,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 52,
          height: 52,
          child:
              Icon(Icons.near_me_rounded, size: 26, color: Color(0xFF111827)),
        ),
      ),
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.20),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(icon, size: 27, color: const Color(0xFF111827)),
        ),
      ),
    );
  }
}

class _NearbyRoutesSheet extends StatelessWidget {
  const _NearbyRoutesSheet({
    required this.details,
    required this.activeRouteId,
    required this.currentPosition,
    required this.locationMessage,
    required this.onRefresh,
  });

  final List<TransitRouteDetail> details;
  final String? activeRouteId;
  final Position? currentPosition;
  final String? locationMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.22,
      maxChildSize: 0.62,
      snap: true,
      snapSizes: const [0.30, 0.62],
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: _GlassSurface(
            radius: 34,
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 18),
              itemCount: details.isEmpty ? 2 : details.length + 1,
              separatorBuilder: (_, index) => index == 0
                  ? const SizedBox(height: 10)
                  : const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _SheetHeader(
                    locationMessage: locationMessage,
                    onRefresh: onRefresh,
                  );
                }
                if (details.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Center(child: Text('ماكو توصية واضحة حالياً')),
                  );
                }
                final detail = details[index - 1];
                return _MobilityRecommendationModule(
                  detail: detail,
                  accent: _tileColor(index - 1),
                  etaMinutes: _etaFor(index - 1, detail),
                  confidence: _confidenceFor(index - 1, detail),
                  fareText: _fareText(detail.route),
                  isActive: activeRouteId == detail.route.id,
                  currentPosition: currentPosition,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Color _tileColor(int index) {
    return switch (index % 4) {
      0 => const Color(0xFF0B78E3),
      1 => const Color(0xFF7B2CBF),
      2 => const Color(0xFFFF8A00),
      _ => const Color(0xFF2563EB),
    };
  }

  int _etaFor(int index, TransitRouteDetail detail) {
    final distance = _distanceToRoute(detail);
    if (distance != null) {
      // Base walking time (approx 80m/min) + base waiting buffer of 5 minutes
      final walkingMinutes = (distance / 80).round();
      return (walkingMinutes + 5).clamp(3, 30);
    }
    return [5, 10, 15, 20][index.clamp(0, 3)];
  }

  String _fareText(TransitRoute route) {
    if (route.fareMin <= 0 && route.fareMax <= 0) return '500 IQD';
    if (route.fareMin == route.fareMax || route.fareMax <= 0) {
      return '${route.fareMin} IQD';
    }
    return '${route.fareMin}-${route.fareMax} IQD';
  }

  String _confidenceFor(int index, TransitRouteDetail detail) {
    final score = detail.route.confidenceScore;
    if (score >= 80 || index == 0) return 'ثقة عالية';
    if (score >= 60) return 'ثقة جيدة';
    return 'ثقة متوسطة';
  }

  double? _distanceToRoute(TransitRouteDetail detail) {
    final position = currentPosition;
    if (position == null || detail.stops.isEmpty) return null;
    return detail.stops
        .map((stop) => Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              stop.lat,
              stop.lng,
            ))
        .reduce((a, b) => a < b ? a : b);
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.locationMessage,
    required this.onRefresh,
  });

  final String? locationMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 4),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onRefresh,
                icon: const Icon(Icons.tune_rounded, size: 24),
                tooltip: 'تحديث',
              ),
              const Spacer(),
              Text(
                'توصيات الحركة الآن',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: const Color(0xFF111827),
                    ),
              ),
            ],
          ),
        ),
        if (locationMessage != null)
          Padding(
            padding: const EdgeInsets.only(left: 9, right: 9, bottom: 4),
            child: Text(
              locationMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }
}

class _MobilityRecommendationModule extends ConsumerWidget {
  const _MobilityRecommendationModule({
    required this.detail,
    required this.accent,
    required this.etaMinutes,
    required this.confidence,
    required this.fareText,
    required this.isActive,
    required this.currentPosition,
  });

  final TransitRouteDetail detail;
  final Color accent;
  final int etaMinutes;
  final String confidence;
  final String fareText;
  final bool isActive;
  final Position? currentPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = detail.route;
    final parts = route.nameAr.split(RegExp(r'\s*[-–—]\s*'));
    final origin = parts.isNotEmpty ? parts.first : route.nameAr;
    final destination = parts.length > 1 ? parts.last : _lastStopName;

    // Construct route arrival request
    final lat = currentPosition?.latitude ?? (detail.stops.isNotEmpty ? detail.stops.first.lat : 0.0);
    final lng = currentPosition?.longitude ?? (detail.stops.isNotEmpty ? detail.stops.first.lng : 0.0);
    final request = RouteArrivalRequest(
      routeId: route.id,
      lat: lat,
      lng: lng,
    );

    final arrivalAsync = ref.watch(routeArrivalProvider(request));

    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => context.push('/routes/${route.id}'),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: isActive ? 0.20 : 0.10),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(Icons.route_rounded, color: accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      RichText(
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                            color: Color(0xFF071827),
                            fontSize: 16.5,
                            height: 1.22,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Tajawal',
                          ),
                          children: [
                            TextSpan(text: origin),
                            const TextSpan(
                              text: '  ←  ',
                              style: TextStyle(color: Color(0xFF1B5E8B)),
                            ),
                            TextSpan(text: destination),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'حسب قربك وحركة الخط الآن',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                arrivalAsync.when(
                  data: (snapshot) {
                    final liveEta = snapshot.selectedVehicle?.etaMinutes;
                    final isLive = liveEta != null;
                    final displayEta = liveEta ?? etaMinutes;

                    return Column(
                      children: [
                        Text(
                          isLive ? '$displayEta' : '~$displayEta',
                          style: TextStyle(
                            color: isLive ? const Color(0xFF17A34A) : const Color(0xFF071827),
                            fontSize: 27,
                            height: 0.9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          isLive ? 'دقائق (لايف)' : 'دقيقة تقديري',
                          style: const TextStyle(
                            color: Color(0xFF071827),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, __) => Column(
                    children: [
                      Text(
                        '~$etaMinutes',
                        style: const TextStyle(
                          color: Color(0xFF071827),
                          fontSize: 27,
                          height: 0.9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'دقيقة تقديري',
                        style: TextStyle(
                          color: Color(0xFF071827),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 7,
              runSpacing: 7,
              children: [
                arrivalAsync.maybeWhen(
                  data: (snapshot) {
                    final isLive = snapshot.selectedVehicle != null;
                    return _SignalPill(
                      label: isLive ? 'تتبع حي نشط' : 'وقت تقديري',
                      icon: isLive ? Icons.sensors : Icons.access_time,
                      color: isLive ? const Color(0xFF17A34A) : Colors.grey.shade600,
                    );
                  },
                  orElse: () => _SignalPill(
                    label: 'وقت تقديري',
                    icon: Icons.access_time,
                    color: Colors.grey.shade600,
                  ),
                ),
                _SignalPill(
                  label: confidence,
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF1B5E8B),
                ),
                _SignalPill(
                  label: fareText,
                  icon: Icons.payments_rounded,
                  color: const Color(0xFFF5A623),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _lastStopName {
    if (detail.stops.isEmpty) return 'الوجهة';
    return detail.stops.last.nameAr;
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: icon == Icons.circle ? 8 : 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 1; index <= 5; index += 1)
          IconButton(
            visualDensity: compact ? VisualDensity.compact : null,
            padding: compact ? EdgeInsets.zero : null,
            constraints: compact
                ? const BoxConstraints.tightFor(width: 34, height: 34)
                : null,
            onPressed: () => onChanged(index),
            icon: Icon(
              index <= value ? Icons.star_rounded : Icons.star_border_rounded,
              color: Colors.amber.shade700,
              size: compact ? 24 : 32,
            ),
          ),
      ],
    );
  }
}
