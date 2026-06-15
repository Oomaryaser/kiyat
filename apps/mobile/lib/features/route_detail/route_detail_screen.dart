import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

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
  bool autoLocateRequested = false;
  String? activeArrivalRequestKey;
  String? lastSelectedVehicleLabel;
  String? persistedRouteId;
  bool arrivalNoticeShown = false;
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(transitRepositoryProvider).saveActiveWaitRouteId(route.id);
        ref.invalidate(activeWaitRouteIdProvider);
      });
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
            .maybeWhen(
              data: (snapshot) => snapshot,
              orElse: RouteArrivalSnapshot.fallback,
            );
    final arrival = arrivalSnapshot?.selectedVehicle;
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
    final nearbyVehicles = arrivalSnapshot?.vehicles ?? sampleVehicles;
    final skippedCount = arrivalSnapshot?.skippedPassedVehicles.length ??
        sampleVehicles.where((vehicle) => vehicle.hasPassedPickup).length;
    final trackingIsStale = _trackingIsStale(arrival);

    return Scaffold(
      appBar: AppBar(
        title: const Text('انتظار الخط'),
        actions: [
          IconButton(
            onPressed: () => _toggleSaved(route.id, !saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            tooltip: saved ? 'محفوظ' : 'حفظ الخط',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WaitingHeader(
            route: route,
            arrival: arrival,
            pickupStop: pickupStop,
            locating: locating,
            hasLocationError: locationError != null,
            waitStatus: waitStatus,
            waitIsVisible: _waitIsVisible,
            trackingIsStale: trackingIsStale,
          ),
          const SizedBox(height: 12),
          _WaitVisibilityCard(
            waitStatus: waitStatus,
            waitLastSyncedAt: waitLastSyncedAt,
            waitSyncError: waitSyncError,
            pickupStop: pickupStop,
            usingCurrentLocation: usingCurrentLocation,
            locating: locating,
            onRetry: effectivePickupLat == null || effectivePickupLng == null
                ? null
                : () => _startPassengerWait(
                      route.id,
                      effectivePickupLat,
                      effectivePickupLng,
                    ).then((_) => _startLocationStream()),
            onStopWaiting: _stopWaiting,
          ),
          const SizedBox(height: 12),
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
            onUseCurrentLocation: () => _useCurrentLocation(stops, route.id),
            onSelectPickup: () => _showPickupSelector(stops, route.id),
            onOpenLocationSettings: _openLocationSettings,
          ),
          const SizedBox(height: 12),
          _WaitingActionBar(
            onOpenMap: () => context.push('/map'),
            onStopWaiting: _stopWaiting,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  bool _trackingIsStale(VehicleArrivalEstimate? arrival) {
    final lastSeenAt = arrival?.lastSeenAt;
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt.toLocal()).inMinutes >= 5;
  }

  bool get _waitIsVisible {
    return waitSessionId != null &&
        waitStatus == 'waiting' &&
        waitSyncError == null;
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
        arrival.etaMinutes <= 2) {
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
          '${arrival.vehicleLabel} توصل تقريباً خلال ${arrival.etaMinutes} دقيقة.',
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
                        .then((_) => _startLocationStream());
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

      final position = await Geolocator.getCurrentPosition();
      final nearestIndex =
          _nearestStopIndex(stops, position.latitude, position.longitude);
      setState(() {
        pickupStopIndex = nearestIndex;
        usingCurrentLocation = true;
        pickupLat = position.latitude;
        pickupLng = position.longitude;
      });
      await _startPassengerWait(routeId, position.latitude, position.longitude);
      _startLocationStream();
    } on LocationServiceDisabledException {
      setState(() {
        locationIssue = _LocationIssue.serviceDisabled;
        locationError = 'خدمة الموقع مطفية. شغلها حتى نحدد أقرب كية عليك.';
      });
    } on PermissionDeniedException catch (error) {
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
    ref.invalidate(activeWaitRouteIdProvider);
    if (!mounted) return;
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

  void _startLocationStream() {
    final waitId = waitSessionId;
    if (waitId == null || waitId.isEmpty) return;
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 35,
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
      setState(() {
        waitStatus = session.status;
        waitLastSyncedAt = DateTime.now();
        waitSyncError = null;
        pickupLat = position.latitude;
        pickupLng = position.longitude;
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
      }
    });
  }

  void _startWaitHeartbeat(double lat, double lng) {
    _waitHeartbeatTimer?.cancel();
    pickupLat = lat;
    pickupLng = lng;
    _waitHeartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final waitId = waitSessionId;
      final nextLat = pickupLat;
      final nextLng = pickupLng;
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
              value: '${arrival!.etaMinutes} دقيقة تقريباً',
            ),
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
  });

  final String? waitStatus;
  final DateTime? waitLastSyncedAt;
  final String? waitSyncError;
  final TransitStop? pickupStop;
  final bool usingCurrentLocation;
  final bool locating;
  final VoidCallback? onRetry;
  final VoidCallback onStopWaiting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isVisible = waitStatus == 'waiting' && waitSyncError == null;
    final isBoarded = waitStatus == 'boarded';
    final icon = isBoarded
        ? Icons.check_circle_outline
        : isVisible
            ? Icons.visibility_outlined
            : waitSyncError != null
                ? Icons.visibility_off_outlined
                : Icons.sync_outlined;
    final color = isBoarded
        ? Colors.blue.shade700
        : isVisible
            ? colors.primary
            : waitSyncError != null
                ? colors.error
                : Colors.orange.shade800;
    final title = isBoarded
        ? 'تم إخفاء انتظارك'
        : isVisible
            ? 'أنت ظاهر للسائقين'
            : waitSyncError != null
                ? 'انتظارك غير ظاهر حالياً'
                : 'دا نثبت انتظارك';
    final subtitle = isBoarded
        ? 'اعتبرناك صعدت الكية، وما راح تظهر كنقطة انتظار للسائق.'
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

class _WaitingActionBar extends StatelessWidget {
  const _WaitingActionBar({
    required this.onOpenMap,
    required this.onStopWaiting,
  });

  final VoidCallback onOpenMap;
  final VoidCallback onStopWaiting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onOpenMap,
            icon: const Icon(Icons.map_outlined),
            label: const Text('عرض الخريطة'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onStopWaiting,
            icon: Icon(Icons.stop_circle_outlined, color: colors.error),
            label: const Text('إيقاف الانتظار'),
          ),
        ),
      ],
    );
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
  });

  final TransitRoute route;
  final VehicleArrivalEstimate? arrival;
  final TransitStop? pickupStop;
  final bool locating;
  final bool hasLocationError;
  final String? waitStatus;
  final bool waitIsVisible;
  final bool trackingIsStale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final etaText = locating
        ? '...'
        : hasLocationError
            ? '-'
            : arrival == null
                ? '-'
                : '${arrival!.etaMinutes}';
    final etaLabel = waitStatus == 'boarded'
        ? 'اعتبرناك صعدت، شلنا نقطة انتظارك من السائق'
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
        color: colors.primary,
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
