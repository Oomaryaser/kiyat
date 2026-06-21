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
  bool waitingEnabled = true;
  String searchQuery = '';
  Position? currentPosition;
  String? locationMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(routeDetailsProvider);
    final savedActiveRouteId = ref.watch(activeWaitRouteIdProvider).maybeWhen(
          data: (routeId) => routeId,
          orElse: () => null,
        );
    return Scaffold(
      extendBody: true,
      body: detailsAsync.when(
        data: (details) {
          final activeId = _effectiveActiveRouteId(
            details.map((detail) => detail.route).toList(),
            savedActiveRouteId,
          );
          return _PassengerHomeDashboard(
            details: details.isEmpty
                ? const [
                    TransitRouteDetail(route: sampleRoute, stops: sampleStops)
                  ]
                : details,
            activeRouteId: activeId,
            searchQuery: searchQuery,
            currentPosition: currentPosition,
            locationMessage: locationMessage,
            onSearchChanged: (value) => setState(() => searchQuery = value),
            onUseCurrentLocation: _loadCurrentPosition,
            onRefresh: _refreshHome,
            onStopWaiting: _cancelWait,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _PassengerHomeDashboard(
          details: const [
            TransitRouteDetail(route: sampleRoute, stops: sampleStops)
          ],
          activeRouteId: sampleRoute.id,
          searchQuery: searchQuery,
          currentPosition: currentPosition,
          locationMessage: 'ما قدرنا نتصل بالخادم، نعرض بيانات محفوظة مؤقتاً.',
          onSearchChanged: (value) => setState(() => searchQuery = value),
          onUseCurrentLocation: _loadCurrentPosition,
          onRefresh: _refreshHome,
          onStopWaiting: _cancelWait,
        ),
      ),
    );
  }

  String? _effectiveActiveRouteId(
      List<TransitRoute> routes, String? savedRouteId) {
    if (!waitingEnabled || routes.isEmpty) return null;
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
    await repository.clearActiveWaitRouteId();
    ref.invalidate(activeWaitRouteIdProvider);
    if (!mounted) return;
    setState(() {
      activeRouteId = null;
      waitingEnabled = false;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeDetail = activeRouteId == null
        ? null
        : details
            .where((detail) => detail.route.id == activeRouteId)
            .firstOrNull;
    if (activeDetail != null) {
      final pickup = _pickupAnchor(activeDetail);
      final request = RouteArrivalRequest(
        routeId: activeDetail.route.id,
        lat: currentPosition?.latitude ?? pickup.latitude,
        lng: currentPosition?.longitude ?? pickup.longitude,
        pickupStopId: currentPosition == null && activeDetail.stops.isNotEmpty
            ? activeDetail.stops.first.id
            : null,
      );
      final arrivalAsync = ref.watch(routeArrivalProvider(request));
      return _ActiveWaitingHome(
        detail: activeDetail,
        currentPosition: currentPosition,
        arrivalAsync: arrivalAsync,
        onUseCurrentLocation: onUseCurrentLocation,
        onOpenLiveMap: () => context.push('/routes/${activeDetail.route.id}'),
        onStopWaiting: onStopWaiting,
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
    required this.arrivalAsync,
    required this.onUseCurrentLocation,
    required this.onOpenLiveMap,
    required this.onStopWaiting,
  });

  final TransitRouteDetail detail;
  final Position? currentPosition;
  final AsyncValue<RouteArrivalSnapshot> arrivalAsync;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onOpenLiveMap;
  final Future<void> Function() onStopWaiting;

  int _pickupDistanceMeters() {
    final position = currentPosition;
    if (position == null || detail.stops.isEmpty) return 50;
    final stop = detail.stops.first;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      stop.lat,
      stop.lng,
    ).round().clamp(35, 850);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = arrivalAsync.maybeWhen(
      data: (value) => value,
      orElse: RouteArrivalSnapshot.fallback,
    );
    final vehicles =
        snapshot.vehicles.isEmpty ? sampleVehicles : snapshot.vehicles;
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
  });

  final String routeName;
  final int etaMinutes;
  final int confidence;
  final bool isLoading;

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
  });

  final List<TransitRouteDetail> details;
  final Position? currentPosition;
  final List<VehicleArrivalEstimate> vehicles;
  final bool isWaitingMode;

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
    final stop = widget.details.first.stops.first;

    final distance = Geolocator.distanceBetween(userLat, userLng, stop.lat, stop.lng);
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
        '/route/v1/foot/$userLng,$userLat;${stop.lng},${stop.lat}',
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
            _walkingPath = [LatLng(userLat, userLng), LatLng(stop.lat, stop.lng)];
          });
          _animateCameraToNavigation();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _walkingPath = [LatLng(userLat, userLng), LatLng(stop.lat, stop.lng)];
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
    final stop = widget.details.first.stops.first;

    double bearing = Geolocator.bearingBetween(userLat, userLng, stop.lat, stop.lng);

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
            : LatLng(widget.details.first.stops.first.lat,
                widget.details.first.stops.first.lng);
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
                    widget.details.first.stops.first.lat,
                    widget.details.first.stops.first.lng,
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
    final idHash = detail.route.id.hashCode.abs();
    final routeOffset = idHash % 8; // 0 to 7 minutes wait variation per route
    if (distance != null) {
      // Base walking time (approx 80m/min) + estimated waiting time (3m + route variation)
      final walkingMinutes = (distance / 80).round();
      return (walkingMinutes + 3 + routeOffset).clamp(3, 22);
    }
    return [3, 6, 8, 12][index.clamp(0, 3)] + (routeOffset % 3);
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

class _MobilityRecommendationModule extends StatelessWidget {
  const _MobilityRecommendationModule({
    required this.detail,
    required this.accent,
    required this.etaMinutes,
    required this.confidence,
    required this.fareText,
    required this.isActive,
  });

  final TransitRouteDetail detail;
  final Color accent;
  final int etaMinutes;
  final String confidence;
  final String fareText;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final route = detail.route;
    final parts = route.nameAr.split(RegExp(r'\s*[-–—]\s*'));
    final origin = parts.isNotEmpty ? parts.first : route.nameAr;
    final destination = parts.length > 1 ? parts.last : _lastStopName;

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
                Column(
                  children: [
                    Text(
                      '$etaMinutes',
                      style: const TextStyle(
                        color: Color(0xFF071827),
                        fontSize: 27,
                        height: 0.9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'دقائق',
                      style: TextStyle(
                        color: Color(0xFF071827),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 7,
              runSpacing: 7,
              children: [
                _SignalPill(
                  label: 'متاح الآن',
                  icon: Icons.circle,
                  color: const Color(0xFF17A34A),
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
