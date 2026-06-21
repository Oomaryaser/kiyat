import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/utils/location_helper.dart';
import '../../shared/data/transit_repository.dart';
import '../../shared/models/transit_models.dart';
import '../../shared/notifications/passenger_notifications.dart';
import '../../shared/settings/passenger_settings.dart';
import '../../shared/widgets/live_route_map.dart';
import '../report/report_bottom_sheet.dart';

class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.routeId});

  final String routeId;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  int? pickupStopIndex;
  bool usingCurrentLocation = true;
  bool locating = true;
  String? locationError;
  _LocationIssue? locationIssue;
  String? waitSessionId;
  String? waitStatus;
  DateTime? waitLastSyncedAt;
  String? waitSyncError;
  double? pickupLat;
  double? pickupLng;
  double? userLat;
  double? userLng;
  bool autoLocateRequested = false;
  String? activeArrivalRequestKey;
  String? lastSelectedVehicleLabel;
  String? persistedRouteId;
  bool arrivalNoticeShown = false;
  bool ratingPromptShown = false;
  RouteArrivalSnapshot? _lastArrivalSnapshot;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _arrivalRefreshTimer;
  Timer? _waitHeartbeatTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _arrivalRefreshTimer?.cancel();
    _waitHeartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(routeDetailProvider(widget.routeId));
    return detailAsync.when(
      data: (detail) => _buildDetail(context, detail),
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('انتظار الخط')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _buildDetail(
        context,
        const TransitRouteDetail(route: sampleRoute, stops: sampleStops),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, TransitRouteDetail detail) {
    final route = detail.route;
    final saved = ref.watch(savedRouteIdsProvider).maybeWhen(
          data: (ids) => ids.contains(route.id),
          orElse: () => false,
        );
    final stops = detail.stops.isEmpty ? sampleStops : detail.stops;
    if (persistedRouteId != route.id) {
      persistedRouteId = route.id;
    }
    if (!autoLocateRequested) {
      autoLocateRequested = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _useCurrentLocation(stops, route.id));
    }
    final pickupStop = _pickupStop(stops);
    final effectivePickupLat = pickupLat ?? pickupStop?.lat;
    final effectivePickupLng = pickupLng ?? pickupStop?.lng;
    final arrivalSnapshot = pickupStop == null
        ? null
        : ref
            .watch(routeArrivalProvider(RouteArrivalRequest(
              routeId: route.id,
              lat: effectivePickupLat ?? pickupStop.lat,
              lng: effectivePickupLng ?? pickupStop.lng,
              pickupStopId: pickupStop.id.isEmpty ? null : pickupStop.id,
            )))
            .valueOrNull;

    if (arrivalSnapshot != null) {
      _lastArrivalSnapshot = arrivalSnapshot;
    }

    final effectiveSnapshot = arrivalSnapshot ?? _lastArrivalSnapshot;
    final arrival = effectiveSnapshot?.selectedVehicle;
    final alertsEnabled = ref.watch(passengerSettingsProvider).maybeWhen(
          data: (settings) => settings.arrivalAlertsEnabled,
          orElse: () => true,
        );
    _scheduleArrivalRefresh(
      route.id,
      effectivePickupLat,
      effectivePickupLng,
      pickupStop?.id,
      arrival,
      alertsEnabled,
    );
    final nearbyVehicles = effectiveSnapshot?.vehicles ?? sampleVehicles;
    final skippedCount = effectiveSnapshot?.skippedPassedVehicles.length ??
        sampleVehicles.where((vehicle) => vehicle.hasPassedPickup).length;
    final trackingIsStale = _trackingIsStale(arrival);

    final savedActiveRouteId = ref.watch(activeWaitRouteIdProvider).maybeWhen(
          data: (routeId) => routeId,
          orElse: () => null,
        );
    final isWaitingForThisRoute = savedActiveRouteId == route.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الخط'),
        actions: [
          IconButton(
            onPressed: () => _toggleSaved(route.id, !saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            tooltip: saved ? 'محفوظ' : 'حفظ الخط',
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/map'),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('الخريطة الحية'),
                ),
              ),
              const SizedBox(width: 10),
              if (isWaitingForThisRoute)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stopWaiting,
                    icon: const Icon(Icons.stop_circle_outlined),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    label: const Text('إيقاف الانتظار'),
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    onPressed: effectivePickupLat == null || effectivePickupLng == null
                        ? null
                        : () => _startPassengerWait(route.id, effectivePickupLat, effectivePickupLng),
                    icon: const Icon(Icons.play_circle_fill_outlined),
                    label: const Text('بدء الانتظار'),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ArrivalCard(
            pickupStop: pickupStop,
            usingCurrentLocation: usingCurrentLocation,
            locating: locating,
            locationError: locationError,
            locationIssue: locationIssue,
            arrival: arrival,
            nearbyVehicles: nearbyVehicles,
            skippedCount: skippedCount,
            trackingIsStale: trackingIsStale,
            stops: stops,
            userLocation: userLat != null && userLng != null ? LatLng(userLat!, userLng!) : null,
            nearestRoutePoint: pickupLat != null && pickupLng != null ? LatLng(pickupLat!, pickupLng!) : null,
            onUseCurrentLocation: () => _useCurrentLocation(stops, route.id),
            onSelectPickup: () => _showPickupSelector(stops, route.id),
            onOpenLocationSettings: _openLocationSettings,
          ),
          const SizedBox(height: 12),
          _RouteDetailsPanel(
            route: route,
            stops: stops,
            pickupStop: pickupStop,
            onReport: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ReportBottomSheet(routeId: route.id),
            ),
          ),
          const SizedBox(height: 92),
        ],
      ),
    );
  }

  bool _trackingIsStale(VehicleArrivalEstimate? arrival) {
    final lastSeenAt = arrival?.lastSeenAt;
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt.toLocal()).inMinutes >= 5;
  }



  Future<void> _toggleSaved(String routeId, bool saved) async {
    await ref.read(transitRepositoryProvider).setRouteSaved(routeId, saved);
    ref.invalidate(savedRouteIdsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(saved ? 'تم حفظ الخط.' : 'تم إزالة الخط من المحفوظة.')),
    );
  }

  void _scheduleArrivalRefresh(
    String routeId,
    double? lat,
    double? lng,
    String? pickupStopId,
    VehicleArrivalEstimate? arrival,
    bool alertsEnabled,
  ) {
    if (lat == null || lng == null) return;
    final request = RouteArrivalRequest(
      routeId: routeId,
      lat: lat,
      lng: lng,
      pickupStopId: pickupStopId?.isEmpty == true ? null : pickupStopId,
    );
    final requestKey = request.toString();
    if (activeArrivalRequestKey != requestKey) {
      activeArrivalRequestKey = requestKey;
      _arrivalRefreshTimer?.cancel();
      _arrivalRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        ref.invalidate(routeArrivalProvider(request));
      });
    }

    final label = arrival?.vehicleLabel;
    if (label != null && label != lastSelectedVehicleLabel) {
      lastSelectedVehicleLabel = label;
      arrivalNoticeShown = false;
    }
    if (alertsEnabled &&
        !arrivalNoticeShown &&
        arrival != null &&
        arrival.notificationHint != null) {
      arrivalNoticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showArrivalAlert(arrival);
      });
    }
  }

  void _showArrivalAlert(VehicleArrivalEstimate arrival) {
    passengerNotifications.showArrivalAlert(
      vehicleLabel: arrival.vehicleLabel,
      etaMinutes: arrival.etaMinutes,
      arrived: arrival.notificationHint == 'arrived',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${arrival.vehicleLabel} قريبة عليك، جهز للصعود.'),
        duration: const Duration(seconds: 4),
      ),
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: const Text('الكية قربت'),
        content: Text(
          arrival.notificationHint == 'arrived'
              ? '${arrival.vehicleLabel} وصلت تقريباً لنقطة صعودك.'
              : '${arrival.vehicleLabel} توصل تقريباً خلال ${arrival.etaMinutes} دقيقة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  TransitStop? _pickupStop(List<TransitStop> stops) {
    if (pickupStopIndex == null ||
        pickupStopIndex! < 0 ||
        pickupStopIndex! >= stops.length) {
      return null;
    }
    return stops[pickupStopIndex!];
  }

  void _showPickupSelector(List<TransitStop> stops, String routeId) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('حدد مكان صعودك على الخط',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              ...stops.indexed.map(
                (item) => ListTile(
                  leading: CircleAvatar(child: Text('${item.$1 + 1}')),
                  title: Text(item.$2.nameAr),
                  subtitle: Text(item.$2.landmarkAr),
                  trailing: pickupStopIndex == item.$1
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () {
                    setState(() {
                      pickupStopIndex = item.$1;
                      usingCurrentLocation = false;
                      pickupLat = item.$2.lat;
                      pickupLng = item.$2.lng;
                      locationError = null;
                      locationIssue = null;
                    });
                    _startPassengerWait(routeId, item.$2.lat, item.$2.lng)
                        .then((_) => _startLocationStream(stops, routeId));
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _useCurrentLocation(
      List<TransitStop> stops, String routeId) async {
    if (!mounted) return;
    setState(() {
      locating = true;
      locationError = null;
      locationIssue = null;
      usingCurrentLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationServiceDisabledException();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw PermissionDeniedException(permission.name);
      }

      final position = await KiyatLocation.getCurrentPosition();
      final nearestIndex =
          _nearestStopIndex(stops, position.latitude, position.longitude);
      if (!mounted) return;

      final nearestOnLine = _findNearestPointOnRouteLine(
        LatLng(position.latitude, position.longitude),
        stops,
      );

      setState(() {
        userLat = position.latitude;
        userLng = position.longitude;
        pickupStopIndex = nearestIndex;
        usingCurrentLocation = true;
        pickupLat = nearestOnLine.latitude;
        pickupLng = nearestOnLine.longitude;
      });
      await _startPassengerWait(routeId, pickupLat!, pickupLng!);
      if (!mounted) return;
      _startLocationStream(stops, routeId);
    } on LocationServiceDisabledException {
      if (!mounted) return;
      setState(() {
        locationIssue = _LocationIssue.serviceDisabled;
        locationError = 'خدمة الموقع مطفية. شغلها حتى نحدد أقرب كية عليك.';
      });
    } on PermissionDeniedException catch (error) {
      if (!mounted) return;
      final deniedForever =
          error.message == LocationPermission.deniedForever.name;
      setState(() {
        locationIssue = deniedForever
            ? _LocationIssue.permissionDeniedForever
            : _LocationIssue.permissionDenied;
        locationError = deniedForever
            ? 'صلاحية الموقع مرفوضة نهائياً. افتح إعدادات التطبيق وفعلها.'
            : 'نحتاج صلاحية الموقع حتى نعرف وين تنتظر على الخط.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        locationIssue = _LocationIssue.unknown;
        locationError =
            'ما قدرنا نحدد موقعك. اختار مكانك يدوياً أو جرّب مرة ثانية.';
      });
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _openLocationSettings() async {
    if (locationIssue == _LocationIssue.serviceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }

  Future<void> _startPassengerWait(
      String routeId, double lat, double lng) async {
    setState(() {
      waitSyncError = null;
    });
    final session =
        await ref.read(transitRepositoryProvider).startPassengerWait(
              routeId: routeId,
              lat: lat,
              lng: lng,
            );
    if (!mounted) return;
    if (session == null || session.id.isEmpty) {
      setState(() {
        waitSyncError =
            'ما قدرنا نظهر انتظارك للسائق. تأكد من الاتصال وجرب مرة ثانية.';
      });
      return;
    }
    setState(() {
      waitSessionId = session.id;
      waitStatus = session.status;
      waitLastSyncedAt = DateTime.now();
      waitSyncError = null;
    });
    await ref
        .read(transitRepositoryProvider)
        .saveActiveWaitSessionId(session.id);
    await ref
        .read(transitRepositoryProvider)
        .saveActiveWaitRouteId(routeId);
    ref.invalidate(activeWaitRouteIdProvider);
    _startWaitHeartbeat(lat, lng);
  }

  Future<void> _stopWaiting() async {
    final repository = ref.read(transitRepositoryProvider);
    final waitId = waitSessionId ?? await repository.loadActiveWaitSessionId();
    if (waitId != null && waitId.isNotEmpty) {
      await repository.cancelPassengerWait(waitId);
    }
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _waitHeartbeatTimer?.cancel();
    _waitHeartbeatTimer = null;
    _arrivalRefreshTimer?.cancel();
    _arrivalRefreshTimer = null;
    await repository.clearActiveWaitRouteId();
    if (!mounted) return;
    ref.invalidate(activeWaitRouteIdProvider);
    setState(() {
      waitSessionId = null;
      waitStatus = 'cancelled';
      waitLastSyncedAt = null;
      waitSyncError = null;
      pickupStopIndex = null;
      pickupLat = null;
      pickupLng = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إيقاف الانتظار، تكدر تختار خط ثاني.')),
    );
    context.go('/');
  }

  void _startLocationStream(List<TransitStop> stops, String routeId) {
    final waitId = waitSessionId;
    if (waitId == null || waitId.isEmpty) return;
    _positionSubscription?.cancel();
    _positionSubscription = KiyatLocation.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) async {
      final session =
          await ref.read(transitRepositoryProvider).updatePassengerWait(
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
          waitSyncError =
              'تحديث موقعك ما وصل للسائق. راح نعيد المحاولة تلقائياً.';
        });
        return;
      }

      LatLng nextPickup = LatLng(pickupLat ?? position.latitude, pickupLng ?? position.longitude);
      if (usingCurrentLocation) {
        nextPickup = _findNearestPointOnRouteLine(
          LatLng(position.latitude, position.longitude),
          stops,
        );
      }

      setState(() {
        waitStatus = session.status;
        waitLastSyncedAt = DateTime.now();
        waitSyncError = null;
        userLat = position.latitude;
        userLng = position.longitude;
        if (usingCurrentLocation) {
          pickupLat = nextPickup.latitude;
          pickupLng = nextPickup.longitude;
        }
      });
      if (session.isBoarded) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
        _waitHeartbeatTimer?.cancel();
        _waitHeartbeatTimer = null;
        await ref.read(transitRepositoryProvider).clearActiveWaitRouteId();
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

  void _startWaitHeartbeat(double lat, double lng) {
    _waitHeartbeatTimer?.cancel();
    pickupLat = lat;
    pickupLng = lng;
    _waitHeartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final waitId = waitSessionId;
      final nextLat = userLat ?? pickupLat;
      final nextLng = userLng ?? pickupLng;
      if (waitId == null ||
          waitId.isEmpty ||
          waitStatus != 'waiting' ||
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
            waitSyncError =
                'تحديث ظهورك للسائق تأخر. راح نعيد المحاولة تلقائياً.';
          });
          return;
        }
        setState(() {
          waitStatus = session.status;
          waitLastSyncedAt = DateTime.now();
          waitSyncError = null;
        });
      });
    });
  }

  int _nearestStopIndex(List<TransitStop> stops, double lat, double lng) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (final item in stops.indexed) {
      final distance =
          Geolocator.distanceBetween(lat, lng, item.$2.lat, item.$2.lng);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = item.$1;
      }
    }
    return bestIndex;
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
    ).whenComplete(commentController.dispose);
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

class _ArrivalCard extends StatelessWidget {
  const _ArrivalCard({
    required this.pickupStop,
    required this.usingCurrentLocation,
    required this.locating,
    required this.locationError,
    required this.locationIssue,
    required this.arrival,
    required this.nearbyVehicles,
    required this.skippedCount,
    required this.trackingIsStale,
    required this.stops,
    required this.onUseCurrentLocation,
    required this.onSelectPickup,
    required this.onOpenLocationSettings,
    this.userLocation,
    this.nearestRoutePoint,
  });

  final TransitStop? pickupStop;
  final bool usingCurrentLocation;
  final bool locating;
  final String? locationError;
  final _LocationIssue? locationIssue;
  final VehicleArrivalEstimate? arrival;
  final List<VehicleArrivalEstimate> nearbyVehicles;
  final int skippedCount;
  final bool trackingIsStale;
  final List<TransitStop> stops;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onSelectPickup;
  final VoidCallback onOpenLocationSettings;
  final LatLng? userLocation;
  final LatLng? nearestRoutePoint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (pickupStop == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: locating ? colors.primary : colors.error,
            borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(locating ? Icons.my_location : Icons.location_off_outlined,
                color: Colors.white),
            const SizedBox(height: 10),
            Text(locating ? 'دا نحدد موقعك الحالي' : 'ما قدرنا نحدد موقعك',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                locating
                    ? 'راح نطلع أقرب نقطة صعود عليك وأقرب كية جاية بنفس الاتجاه.'
                    : 'اختار مكانك يدوياً أو جرّب إعادة تحديد الموقع.',
                style: TextStyle(color: Colors.white)),
            if (locationError != null) ...[
              const SizedBox(height: 10),
              Text(locationError!,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: locating ? null : onUseCurrentLocation,
                    icon: locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.near_me_outlined),
                    label: Text(locating ? 'لحظة...' : 'حاول مرة ثانية'),
                  ),
                ),
                const SizedBox(width: 8),
                if (locationIssue != null) ...[
                  IconButton.filledTonal(
                    onPressed: onOpenLocationSettings,
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'إعدادات الموقع',
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton.filledTonal(
                  onPressed: onSelectPickup,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  tooltip: 'اختيار يدوي',
                ),
              ],
            ),
          ],
        ),
      );
    }

    final selectedPickupStop = pickupStop!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.primary.withValues(alpha: 0.18))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LocationModeStrip(
            pickupStop: selectedPickupStop,
            usingCurrentLocation: usingCurrentLocation,
            locating: locating,
            locationError: locationError,
            locationIssue: locationIssue,
            onUseCurrentLocation: onUseCurrentLocation,
            onSelectPickup: onSelectPickup,
            onOpenLocationSettings: onOpenLocationSettings,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: LiveRouteMap(
              stops: stops,
              vehicles: nearbyVehicles,
              pickupStop: selectedPickupStop,
              selectedVehicle: arrival,
              compact: true,
              userLocation: userLocation,
              nearestRoutePoint: nearestRoutePoint,
            ),
          ),
          const SizedBox(height: 12),
          if (arrival == null)
            _NoArrivalPanel(
              pickupStop: selectedPickupStop,
              usingCurrentLocation: usingCurrentLocation,
            )
          else ...[
            _StatusLine(
              icon: Icons.directions_bus_filled,
              label: 'أقرب كية',
              value:
                  '${arrival!.vehicleLabel} قرب ${arrival!.nearStopName}، تبعد ${arrival!.distanceMeters} م',
            ),
            const SizedBox(height: 8),
            _StatusLine(
              icon: Icons.timer_outlined,
              label: 'توصل خلال',
              value:
                  '${arrival!.etaMinutes} دقيقة تقريباً (${arrival!.etaConfidenceLabel})',
            ),
            if (arrival!.lastSeenSeconds != null) ...[
              const SizedBox(height: 8),
              _StatusLine(
                icon: Icons.sensors,
                label: 'آخر تحديث',
                value: _secondsAgoArabic(arrival!.lastSeenSeconds!),
                color: arrival!.etaConfidence == 'low'
                    ? Colors.red.shade700
                    : null,
              ),
            ],
            if (skippedCount > 0) ...[
              const SizedBox(height: 8),
              _StatusLine(
                icon: Icons.history_toggle_off,
                label: 'تم تجاهل',
                value: '$skippedCount كية لأنها عدّت مكانك',
                color: Colors.orange.shade800,
              ),
            ],
            if (trackingIsStale) ...[
              const SizedBox(height: 8),
              _StatusLine(
                icon: Icons.sensors_off_outlined,
                label: 'تنبيه',
                value: 'تتبع الكية متأخر، اعتبر الوقت تقريبي.',
                color: Colors.red.shade700,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LocationModeStrip extends StatelessWidget {
  const _LocationModeStrip({
    required this.pickupStop,
    required this.usingCurrentLocation,
    required this.locating,
    required this.locationError,
    required this.locationIssue,
    required this.onUseCurrentLocation,
    required this.onSelectPickup,
    required this.onOpenLocationSettings,
  });

  final TransitStop pickupStop;
  final bool usingCurrentLocation;
  final bool locating;
  final String? locationError;
  final _LocationIssue? locationIssue;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onSelectPickup;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = locating
        ? 'دا نثبت موقعك الحالي'
        : usingCurrentLocation
            ? 'موقعك الحالي مفعّل'
            : 'مختار نقطة صعود يدوياً';
    final subtitle = locationError ??
        (usingCurrentLocation
            ? 'نحسب أقرب كية عليك قرب ${pickupStop.nameAr}.'
            : 'مكان الصعود اليدوي قرب ${pickupStop.nameAr}.');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            usingCurrentLocation ? Icons.my_location : Icons.place_outlined,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          if (locationIssue != null) ...[
            IconButton.filledTonal(
              onPressed: onOpenLocationSettings,
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'إعدادات الموقع',
            ),
            const SizedBox(width: 6),
          ],
          IconButton.outlined(
            onPressed: locating ? null : onUseCurrentLocation,
            icon: locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me_outlined),
            tooltip: 'استخدام موقعي الحالي',
          ),
          const SizedBox(width: 6),
          IconButton.outlined(
            onPressed: onSelectPickup,
            icon: const Icon(Icons.edit_location_alt_outlined),
            tooltip: 'اختيار يدوي',
          ),
        ],
      ),
    );
  }
}

class _NoArrivalPanel extends StatelessWidget {
  const _NoArrivalPanel({
    required this.pickupStop,
    required this.usingCurrentLocation,
  });

  final TransitStop pickupStop;
  final bool usingCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return _InfoTile(
      icon: Icons.sensors_off_outlined,
      title: 'ماكو تتبع حي حالياً',
      subtitle: usingCurrentLocation
          ? 'موقعك الحالي قرب ${pickupStop.nameAr}. راح نعرض أقرب كية أول ما تظهر.'
          : 'مكان صعودك قرب ${pickupStop.nameAr}. راح نعرض أقرب كية أول ما تظهر.',
    );
  }
}

enum _LocationIssue {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unknown,
}

class _PassengerNextStepCard extends StatelessWidget {
  const _PassengerNextStepCard({
    required this.waitIsVisible,
    required this.waitSyncError,
    required this.locating,
    required this.arrival,
    required this.pickupStop,
    required this.trackingIsStale,
    required this.onRetry,
    required this.onUseCurrentLocation,
    this.userLocation,
    this.nearestRoutePoint,
  });

  final bool waitIsVisible;
  final String? waitSyncError;
  final bool locating;
  final VehicleArrivalEstimate? arrival;
  final TransitStop? pickupStop;
  final bool trackingIsStale;
  final VoidCallback? onRetry;
  final VoidCallback onUseCurrentLocation;
  final LatLng? userLocation;
  final LatLng? nearestRoutePoint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    double? distanceMeters;
    if (userLocation != null && nearestRoutePoint != null) {
      distanceMeters = Geolocator.distanceBetween(
        userLocation!.latitude,
        userLocation!.longitude,
        nearestRoutePoint!.latitude,
        nearestRoutePoint!.longitude,
      );
    }
    final isOffRoute = distanceMeters != null && distanceMeters > 35;
    
    final title = _getTitle(isOffRoute);
    final subtitle = _getSubtitle(isOffRoute, distanceMeters);
    final icon = _getIcon(isOffRoute);
    final color = _getColor(colors, isOffRoute);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (waitSyncError != null || locating) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: locating ? null : onUseCurrentLocation,
                    icon: locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(locating ? 'دا نحدد...' : 'حدث موقعي'),
                  ),
                ),
                if (waitSyncError != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('أظهرني للسائق'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _getTitle(bool isOffRoute) {
    if (locating) return 'نثبت موقعك';
    if (waitSyncError != null) return 'أنت غير ظاهر للسائق';
    if (!waitIsVisible) return 'دا نظهرك للسائق';
    if (isOffRoute) return 'توجه إلى مسار الخط';
    if (arrival == null) return 'أنت ظاهر، انتظر كية';
    if (trackingIsStale) return 'الكية ظاهرة بس التحديث متأخر';
    if (arrival!.etaMinutes <= 2) return 'جهز، الكية قريبة';
    return 'أنت ظاهر، الكية بالطريق';
  }

  String _getSubtitle(bool isOffRoute, double? distanceMeters) {
    if (locating) return 'خلي الموقع مفتوح حتى نحدد أقرب نقطة صعود.';
    if (waitSyncError != null) return waitSyncError!;
    if (!waitIsVisible) return 'نرسل موقع انتظارك للسائقين على هذا الخط.';
    if (isOffRoute && distanceMeters != null) {
      final distanceRounded = distanceMeters.round();
      final vehicleText = arrival == null
          ? 'ماكو كية قريبة حالياً'
          : 'والكية ${arrival!.vehicleLabel} راح توصل خلال ${arrival!.etaMinutes} دقيقة تقريباً';
      return 'امشي روح لهذه النقطة (على بعد $distanceRounded متر) لكي تظهر كراكب، $vehicleText.';
    }
    final place =
        pickupStop == null ? 'مكانك الحالي' : 'قرب ${pickupStop!.nameAr}';
    if (arrival == null) {
      return 'السائقين يشوفونك عند $place. أول كية تظهر راح نعرضها هنا.';
    }
    final lastSeen = arrival!.lastSeenSeconds == null
        ? ''
        : '، آخر تحديث ${_secondsAgoArabic(arrival!.lastSeenSeconds!)}';
    return '${arrival!.vehicleLabel} تبعد ${arrival!.distanceMeters} م وتوصل خلال ${arrival!.etaMinutes} دقيقة تقريباً (${arrival!.etaConfidenceLabel}$lastSeen).';
  }

  IconData _getIcon(bool isOffRoute) {
    if (locating) return Icons.my_location;
    if (waitSyncError != null) return Icons.visibility_off_outlined;
    if (!waitIsVisible) return Icons.sync_outlined;
    if (isOffRoute) return Icons.directions_walk;
    if (arrival == null) return Icons.visibility_outlined;
    if (arrival!.etaMinutes <= 2) return Icons.notifications_active_outlined;
    return Icons.directions_bus_filled;
  }

  Color _getColor(ColorScheme colors, bool isOffRoute) {
    if (waitSyncError != null) return colors.error;
    if (locating || !waitIsVisible) return Colors.orange.shade800;
    if (isOffRoute) return Colors.orange.shade800;
    if (arrival != null && arrival!.etaMinutes <= 2) {
      return Colors.blue.shade700;
    }
    return colors.primary;
  }
}

class _WaitVisibilityCard extends StatelessWidget {
  const _WaitVisibilityCard({
    required this.waitStatus,
    required this.waitLastSyncedAt,
    required this.waitSyncError,
    required this.pickupStop,
    required this.usingCurrentLocation,
    required this.locating,
    required this.onRetry,
    required this.onStopWaiting,
    this.userLocation,
    this.nearestRoutePoint,
  });

  final String? waitStatus;
  final DateTime? waitLastSyncedAt;
  final String? waitSyncError;
  final TransitStop? pickupStop;
  final bool usingCurrentLocation;
  final bool locating;
  final VoidCallback? onRetry;
  final VoidCallback onStopWaiting;
  final LatLng? userLocation;
  final LatLng? nearestRoutePoint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    double? distanceMeters;
    if (userLocation != null && nearestRoutePoint != null) {
      distanceMeters = Geolocator.distanceBetween(
        userLocation!.latitude,
        userLocation!.longitude,
        nearestRoutePoint!.latitude,
        nearestRoutePoint!.longitude,
      );
    }
    final isOffRoute = distanceMeters != null && distanceMeters > 35;
    
    final isVisible = waitStatus == 'waiting' && waitSyncError == null && !isOffRoute;
    final isBoarded = waitStatus == 'boarded';
    final icon = isBoarded
        ? Icons.check_circle_outline
        : isVisible
            ? Icons.visibility_outlined
            : isOffRoute
                ? Icons.visibility_off_outlined
                : waitSyncError != null
                    ? Icons.visibility_off_outlined
                    : Icons.sync_outlined;
    final color = isBoarded
        ? Colors.blue.shade700
        : isVisible
            ? colors.primary
            : isOffRoute
                ? Colors.orange.shade800
                : waitSyncError != null
                    ? colors.error
                    : Colors.orange.shade800;
    final title = isBoarded
        ? 'تم إخفاء انتظارك'
        : isVisible
            ? 'أنت ظاهر للسائقين'
            : isOffRoute
                ? 'انتظارك غير ظاهر حالياً (خارج الخط)'
                : waitSyncError != null
                    ? 'انتظارك غير ظاهر حالياً'
                    : 'دا نثبت انتظارك';
    final subtitle = isBoarded
        ? 'اعتبرناك صعدت الكية، وما راح تظهر كنقطة انتظار للسائق.'
        : isOffRoute
            ? 'أنت على بعد ${distanceMeters.round()} متر من الخط. تقرّب من الشارع العام حتى تظهر للسواق.'
            : waitSyncError ??
                (isVisible
                    ? _visibleMessage
                    : 'نرسل موقع صعودك للسائقين على هذا الخط.');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
                if (waitLastSyncedAt != null && isVisible) ...[
                  const SizedBox(height: 6),
                  Text(
                    'آخر تحديث وصل قبل ${_relativeArabic(waitLastSyncedAt!)}',
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (waitSyncError != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: locating ? null : onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة الإظهار'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onStopWaiting,
                        child: const Text('إيقاف الانتظار'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _visibleMessage {
    final place = pickupStop == null ? 'موقعك' : 'قرب ${pickupStop!.nameAr}';
    final source =
        usingCurrentLocation ? 'من موقعك الحالي' : 'من اختيارك اليدوي';
    return 'نقطة انتظارك ظاهرة للسائق $place، وتتحدث $source.';
  }
}

class _WaitingHeader extends StatelessWidget {
  const _WaitingHeader({
    required this.route,
    required this.arrival,
    required this.pickupStop,
    required this.locating,
    required this.hasLocationError,
    required this.waitStatus,
    required this.waitIsVisible,
    required this.trackingIsStale,
    this.userLocation,
    this.nearestRoutePoint,
  });

  final TransitRoute route;
  final VehicleArrivalEstimate? arrival;
  final TransitStop? pickupStop;
  final bool locating;
  final bool hasLocationError;
  final String? waitStatus;
  final bool waitIsVisible;
  final bool trackingIsStale;
  final LatLng? userLocation;
  final LatLng? nearestRoutePoint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    double? distanceMeters;
    if (userLocation != null && nearestRoutePoint != null) {
      distanceMeters = Geolocator.distanceBetween(
        userLocation!.latitude,
        userLocation!.longitude,
        nearestRoutePoint!.latitude,
        nearestRoutePoint!.longitude,
      );
    }
    final isOffRoute = distanceMeters != null && distanceMeters > 35;
    
    final etaText = locating
        ? '...'
        : hasLocationError
            ? '-'
            : arrival == null
                ? '-'
                : '${arrival!.etaMinutes}';
    final etaLabel = waitStatus == 'boarded'
        ? 'اعتبرناك صعدت، شلنا نقطة انتظارك من السائق'
        : isOffRoute
            ? 'أنت غير ظاهر للسواق حالياً (ابتعدت عن الخط)'
            : waitIsVisible
                ? 'أنت ظاهر للسائقين على هذا الخط'
                : trackingIsStale
                    ? 'التتبع متأخر، الوقت تقريبي'
                    : locating
                        ? 'دا نحدد موقعك'
                        : hasLocationError
                            ? 'الموقع يحتاج تحديث'
                            : arrival == null
                                ? 'بانتظار ظهور كية'
                                : 'دقيقة وتوصل لمكانك';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isOffRoute ? Colors.orange.shade800 : colors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_bus_filled,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('أنت تنتظر',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w700)),
                    Text(route.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(etaText,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(etaLabel,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.place_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pickupStop == null
                      ? 'نحدد أقرب نقطة صعود عليك'
                      : 'مكان صعودك قرب ${pickupStop!.nameAr}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _relativeArabic(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.inSeconds < 45) return 'ثواني';
  if (difference.inMinutes < 60) return '${difference.inMinutes} دقيقة';
  return '${difference.inHours} ساعة';
}

String _secondsAgoArabic(int seconds) {
  if (seconds < 45) return 'قبل ثواني';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return 'قبل $minutes دقيقة';
  return 'قبل ${(minutes / 60).round()} ساعة';
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final lineColor = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 18, color: lineColor),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w800)),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route});

  final TransitRoute route;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniFact(
              icon: Icons.payments_outlined,
              label: 'الأجرة',
              value: '${route.fareMin} - ${route.fareMax} د.ع',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniFact(
              icon: Icons.schedule,
              label: 'الدوام',
              value:
                  '${route.operatingHoursStart} - ${route.operatingHoursEnd}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniFact(
              icon: Icons.verified_outlined,
              label: 'الثقة',
              value: '${route.confidenceScore}%',
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteDetailsPanel extends StatelessWidget {
  const _RouteDetailsPanel({
    required this.route,
    required this.stops,
    required this.pickupStop,
    required this.onReport,
  });

  final TransitRoute route;
  final List<TransitStop> stops;
  final TransitStop? pickupStop;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        collapsedShape:
            const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        leading: Icon(Icons.route_outlined, color: colors.primary),
        title: const Text('تفاصيل الخط',
            style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: const Text('الأجرة، الدوام، ونقاط الدلالة'),
        children: [
          _RouteSummary(route: route),
          const SizedBox(height: 12),
          _LandmarkStrip(stops: stops, pickupStop: pickupStop),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onReport,
            icon: Icon(Icons.report_outlined, color: colors.error),
            label: const Text('بلّغ عن تغيير بالخط'),
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.primary, size: 20),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _LandmarkStrip extends StatelessWidget {
  const _LandmarkStrip({required this.stops, required this.pickupStop});

  final List<TransitStop> stops;
  final TransitStop? pickupStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('مسار الخط',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ...stops.indexed.map(
            (item) => _LandmarkRow(
              index: item.$1,
              stop: item.$2,
              isPickup: pickupStop?.id == item.$2.id,
              isLast: item.$1 == stops.length - 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandmarkRow extends StatelessWidget {
  const _LandmarkRow({
    required this.index,
    required this.stop,
    required this.isPickup,
    required this.isLast,
  });

  final int index;
  final TransitStop stop;
  final bool isPickup;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: isPickup
                  ? colors.primary
                  : colors.primary.withValues(alpha: 0.12),
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: isPickup ? Colors.white : colors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 30,
                color: colors.primary.withValues(alpha: 0.16),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(stop.nameAr,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    if (isPickup)
                      Text('مكانك',
                          style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w900)),
                  ],
                ),
                Text(stop.landmarkAr,
                    style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle)
            ]),
          ),
        ],
      ),
    );
  }
}
