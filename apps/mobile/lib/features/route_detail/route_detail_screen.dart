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
  double? pickupLat;
  double? pickupLng;
  double? userLat;
  double? userLng;
  bool autoLocateRequested = false;
  String? activeArrivalRequestKey;
  String? lastSelectedVehicleLabel;
  String? persistedRouteId;
  bool arrivalNoticeShown = false;
  RouteArrivalSnapshot? _lastArrivalSnapshot;
  Timer? _arrivalRefreshTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _arrivalRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(routeDetailProvider(widget.routeId));
    return detailAsync.when(
      data: (detail) => _buildDetail(context, detail),
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الخط')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الخط')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'حدث خطأ في تحميل تفاصيل الخط',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString().contains('SocketException') || error.toString().contains('Network')
                      ? 'يرجى التحقق من اتصالك بالإنترنت والمحاولة مجدداً.'
                      : 'فشل الاتصال بالخادم. يرجى المحاولة لاحقاً.',
                  style: TextStyle(color: Colors.grey[600], fontFamily: 'Tajawal'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(routeDetailProvider(widget.routeId)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Tajawal')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, TransitRouteDetail detail) {
    final colors = Theme.of(context).colorScheme;
    final route = detail.route;
    final saved = ref.watch(savedRouteIdsProvider).maybeWhen(
          data: (ids) => ids.contains(route.id),
          orElse: () => false,
        );
    final savedActiveRouteId = ref.watch(activeWaitRouteIdProvider).maybeWhen(
          data: (routeId) => routeId,
          orElse: () => null,
        );
    final isWaitingForThisRoute = savedActiveRouteId == route.id;
    final stops = detail.stops;
    if (persistedRouteId != route.id) {
      persistedRouteId = route.id;
    }
    if (!autoLocateRequested) {
      autoLocateRequested = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _useCurrentLocation(stops, route.id, isWaitingForThisRoute));
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
    final nearbyVehicles = effectiveSnapshot?.vehicles ?? const [];
    final skippedCount = effectiveSnapshot?.skippedPassedVehicles.length ?? 0;
    final trackingIsStale = _trackingIsStale(arrival);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تفاصيل الخط',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontFamily: 'Tajawal',
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: () => _toggleSaved(route.id, !saved),
            icon: Icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: saved ? colors.primary : colors.onSurface,
            ),
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
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    backgroundColor: colors.primary.withValues(alpha: 0.1),
                    foregroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: const Text(
                    'الخريطة الحية',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (isWaitingForThisRoute)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stopWaiting,
                    icon: const Icon(Icons.stop_circle_outlined),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      foregroundColor: const Color(0xFFB42318),
                      side: BorderSide(
                        color: const Color(0xFFB42318).withValues(alpha: 0.18),
                      ),
                      backgroundColor: const Color(0xFFFFF1F0).withValues(alpha: 0.72),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    label: const Text(
                      'إيقاف الانتظار',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    onPressed: effectivePickupLat == null || effectivePickupLng == null
                        ? null
                        : () => _startPassengerWait(route.id, effectivePickupLat, effectivePickupLng),
                    icon: const Icon(Icons.play_circle_fill_outlined),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 4,
                      shadowColor: colors.primary.withValues(alpha: 0.25),
                    ),
                    label: const Text(
                      'بدء الانتظار',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF3F8FC), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
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
              onUseCurrentLocation: () => _useCurrentLocation(stops, route.id, isWaitingForThisRoute),
              onSelectPickup: () => _showPickupSelector(stops, route.id, isWaitingForThisRoute),
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

  void _showPickupSelector(List<TransitStop> stops, String routeId, bool isWaiting) {
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
                    if (isWaiting) {
                      _startPassengerWait(routeId, item.$2.lat, item.$2.lng);
                    }
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
      List<TransitStop> stops, String routeId, bool isWaiting) async {
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
      if (isWaiting) {
        await _startPassengerWait(routeId, pickupLat!, pickupLng!);
      }
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
    final session =
        await ref.read(transitRepositoryProvider).startPassengerWait(
              routeId: routeId,
              lat: lat,
              lng: lng,
            );
    if (!mounted) return;
    if (session == null || session.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ما قدرنا نظهر انتظارك للسائق. تأكد من الاتصال وجرب مرة ثانية.'),
        ),
      );
      return;
    }
    await ref
        .read(transitRepositoryProvider)
        .saveActiveWaitSessionId(session.id);
    await ref
        .read(transitRepositoryProvider)
        .saveActiveWaitRouteId(routeId);
    ref.invalidate(activeWaitRouteIdProvider);
    
    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _stopWaiting() async {
    final repository = ref.read(transitRepositoryProvider);
    final waitId = await repository.loadActiveWaitSessionId();
    if (waitId != null && waitId.isNotEmpty) {
      await repository.cancelPassengerWait(waitId);
    }
    await repository.clearActiveWaitRouteId();
    if (!mounted) return;
    ref.invalidate(activeWaitRouteIdProvider);
    setState(() {
      pickupStopIndex = null;
      pickupLat = null;
      pickupLng = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إيقاف الانتظار، تكدر تختار خط ثاني.')),
    );
    context.go('/');
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
      final cardColor = locating ? colors.primary : colors.error;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cardColor.withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                locating ? Icons.my_location : Icons.location_off_outlined,
                color: cardColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              locating ? 'دا نحدد موقعك الحالي' : 'ما قدرنا نحدد موقعك',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: cardColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              locating
                  ? 'راح نطلع أقرب نقطة صعود عليك وأقرب كية جاية بنفس الاتجاه.'
                  : 'اختار مكانك يدوياً أو جرّب إعادة تحديد الموقع.',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            if (locationError != null) ...[
              const SizedBox(height: 10),
              Text(
                locationError!,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  color: cardColor,
                ),
              ),
            ],
            const SizedBox(height: 16),
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
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
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
              const SizedBox(height: 10),
              _StatusLine(
                icon: Icons.timer_outlined,
                label: 'توصل خلال',
                value:
                    '${arrival!.etaMinutes} دقيقة تقريباً (${arrival!.etaConfidenceLabel})',
              ),
              if (arrival!.lastSeenSeconds != null) ...[
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                _StatusLine(
                  icon: Icons.history_toggle_off,
                  label: 'تم تجاهل',
                  value: '$skippedCount كية لأنها عدّت مكانك',
                  color: Colors.orange.shade800,
                ),
              ],
              if (trackingIsStale) ...[
                const SizedBox(height: 10),
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
        color: colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              usingCurrentLocation ? Icons.my_location : Icons.place_outlined,
              color: colors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
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
            style: IconButton.styleFrom(
              side: BorderSide(color: colors.primary.withValues(alpha: 0.15)),
            ),
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
            style: IconButton.styleFrom(
              side: BorderSide(color: colors.primary.withValues(alpha: 0.15)),
            ),
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
    final colors = Theme.of(context).colorScheme;
    final lineColor = color ?? colors.primary;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: lineColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: lineColor),
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: color ?? const Color(0xFF173244),
            ),
          ),
        ),
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
    return _GlassCard(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: Border.all(color: Colors.transparent),
        collapsedShape: Border.all(color: Colors.transparent),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.route_outlined, color: colors.primary, size: 20),
        ),
        title: const Text(
          'تفاصيل الخط',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w900,
            fontSize: 15.5,
          ),
        ),
        subtitle: const Text(
          'الأجرة، الدوام، ونقاط الدلالة',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        children: [
          _RouteSummary(route: route),
          const SizedBox(height: 12),
          _LandmarkStrip(stops: stops, pickupStop: pickupStop),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReport,
              icon: Icon(Icons.report_outlined, color: colors.error, size: 18),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                foregroundColor: colors.error,
                side: BorderSide(
                  color: colors.error.withValues(alpha: 0.18),
                ),
                backgroundColor: colors.error.withValues(alpha: 0.03),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              label: const Text(
                'بلّغ عن تغيير بالخط',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
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
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;
  static const double radius = 28;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF071827).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF1B5E8B).withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}
