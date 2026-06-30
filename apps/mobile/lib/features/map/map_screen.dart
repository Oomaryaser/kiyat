import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/location_helper.dart';

import '../../shared/data/transit_repository.dart';
import '../../shared/ui/kiyat_logo.dart';
import '../../shared/models/transit_models.dart';
import '../../shared/widgets/live_route_map.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  Timer? _refreshTimer;
  String? _selectedRouteId;
  Position? _currentPosition;
  RouteArrivalRequest? _lastArrivalRequest;
  bool _locating = true;
  String? _locationStatus;

  @override
  void initState() {
    super.initState();
    _useCurrentLocation();
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final request = _lastArrivalRequest;
      if (request != null) {
        ref.invalidate(routeArrivalProvider(request));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(routeDetailsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KiyatLogo(size: 30, showWordmark: false),
            SizedBox(width: 8),
            Text('الخريطة الحية'),
          ],
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.88),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: detailsAsync.when(
        data: (details) => _LiveRoutesMapBody(
          details: details,
          selectedRouteId: _selectedRouteId,
          currentPosition: _currentPosition,
          locating: _locating,
          locationStatus: _locationStatus,
          onSelectRoute: (routeId) =>
              setState(() => _selectedRouteId = routeId),
          onUseCurrentLocation: _useCurrentLocation,
          onArrivalRequestChanged: (request) => _lastArrivalRequest = request,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'فشل الاتصال بالخريطة الحية',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Tajawal'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'يرجى التحقق من اتصالك بالإنترنت والمحاولة مجدداً.',
                  style: TextStyle(color: Colors.grey, fontFamily: 'Tajawal'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(routeDetailsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Tajawal')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      _locating = true;
      _locationStatus = null;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationStatus = 'شغّل خدمة الموقع حتى نخلي الخريطة حسب مكانك.';
      });
      return;
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationStatus = 'فعّل صلاحية الموقع حتى نحسب أقرب كية عليك.';
        });
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
        _currentPosition = position;
        _locating = false;
        _locationStatus = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationStatus =
            'ما قدرنا نحدث موقعك، نعرض أقرب نقطة على الخط مؤقتاً.';
      });
    }
  }
}

class _LiveRoutesMapBody extends ConsumerWidget {
  const _LiveRoutesMapBody({
    required this.details,
    required this.selectedRouteId,
    required this.currentPosition,
    required this.locating,
    required this.locationStatus,
    required this.onSelectRoute,
    required this.onUseCurrentLocation,
    required this.onArrivalRequestChanged,
  });

  final List<TransitRouteDetail> details;
  final String? selectedRouteId;
  final Position? currentPosition;
  final bool locating;
  final String? locationStatus;
  final ValueChanged<String> onSelectRoute;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<RouteArrivalRequest> onArrivalRequestChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _selectedDetail;
    final pickupStop = _pickupStopFor(selected);
    final arrivalRequest = RouteArrivalRequest(
      routeId: selected.route.id,
      lat: pickupStop.lat,
      lng: pickupStop.lng,
      pickupStopId: currentPosition == null ? pickupStop.id : null,
    );
    onArrivalRequestChanged(arrivalRequest);

    final arrivalAsync = ref.watch(routeArrivalProvider(arrivalRequest));
    final arrival = arrivalAsync.valueOrNull;
    final selectedVehicle = arrival?.selectedVehicle;
    final vehicles = arrival?.vehicles ?? const <VehicleArrivalEstimate>[];
    final otherLines = details
        .where((detail) => detail.route.id != selected.route.id)
        .map((detail) => detail.stops)
        .where((stops) => stops.length > 1)
        .toList();

    return Stack(
      children: [
        LiveRouteMap(
          stops: selected.stops,
          vehicles: vehicles,
          pickupStop: pickupStop,
          selectedVehicle: selectedVehicle,
          extraRouteLines: otherLines,
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: _RoutesPreviewPanel(
              details: details,
              selected: selected,
              selectedVehicle: selectedVehicle,
              isLoadingArrival: arrivalAsync.isLoading,
              usingCurrentLocation: currentPosition != null,
              locating: locating,
              locationStatus: locationStatus,
              onSelectRoute: onSelectRoute,
              onUseCurrentLocation: onUseCurrentLocation,
            ),
          ),
        ),
      ],
    );
  }

  TransitRouteDetail get _selectedDetail {
    return details.firstWhere(
      (detail) => detail.route.id == selectedRouteId,
      orElse: () => details.first,
    );
  }

  TransitStop _pickupStopFor(TransitRouteDetail detail) {
    if (currentPosition != null) {
      return TransitStop(
        id: 'current_location',
        nameAr: 'موقعك الحالي',
        landmarkAr: 'معاينة لايف حسب موقعك',
        lat: currentPosition!.latitude,
        lng: currentPosition!.longitude,
        isMajor: false,
      );
    }
    if (detail.stops.length > 1) return detail.stops[1];
    return detail.stops.first;
  }
}

class _RoutesPreviewPanel extends StatelessWidget {
  const _RoutesPreviewPanel({
    required this.details,
    required this.selected,
    required this.selectedVehicle,
    required this.isLoadingArrival,
    required this.usingCurrentLocation,
    required this.locating,
    required this.locationStatus,
    required this.onSelectRoute,
    required this.onUseCurrentLocation,
  });

  final List<TransitRouteDetail> details;
  final TransitRouteDetail selected;
  final VehicleArrivalEstimate? selectedVehicle;
  final bool isLoadingArrival;
  final bool usingCurrentLocation;
  final bool locating;
  final String? locationStatus;
  final ValueChanged<String> onSelectRoute;
  final VoidCallback onUseCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final etaText = selectedVehicle == null
        ? (isLoadingArrival ? 'جاري التحديث' : 'ماكو كية قريبة')
        : 'الأقرب ${selectedVehicle!.etaMinutes} د';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.directions_bus_filled,
                      color: AppColors.navy),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.route.nameAr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${details.length} خطوط على الخريطة • $etaText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/routes/${selected.route.id}'),
                  icon: const Icon(Icons.near_me),
                  label: const Text('انتظر'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MapLocationMode(
              usingCurrentLocation: usingCurrentLocation,
              locating: locating,
              locationStatus: locationStatus,
              onUseCurrentLocation: onUseCurrentLocation,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: details.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final detail = details[index];
                  final isSelected = detail.route.id == selected.route.id;
                  return _RouteMapChip(
                    detail: detail,
                    isSelected: isSelected,
                    onTap: () => onSelectRoute(detail.route.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLocationMode extends StatelessWidget {
  const _MapLocationMode({
    required this.usingCurrentLocation,
    required this.locating,
    required this.locationStatus,
    required this.onUseCurrentLocation,
  });

  final bool usingCurrentLocation;
  final bool locating;
  final String? locationStatus;
  final VoidCallback onUseCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = locating
        ? 'دا نحدد موقعك'
        : usingCurrentLocation
            ? 'موقعك الحالي مفعّل'
            : 'الخريطة تستخدم أقرب نقطة على الخط';
    final subtitle = locationStatus ??
        (usingCurrentLocation
            ? 'الأوقات محسوبة حسب مكانك الحالي.'
            : 'فعّل موقعك حتى تصير الحسابات أدق.');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            usingCurrentLocation ? Icons.my_location : Icons.location_searching,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: locating ? null : onUseCurrentLocation,
            icon: locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me_outlined),
            label: Text(usingCurrentLocation ? 'تحديث' : 'استخدمه'),
          ),
        ],
      ),
    );
  }
}

class _RouteMapChip extends StatelessWidget {
  const _RouteMapChip({
    required this.detail,
    required this.isSelected,
    required this.onTap,
  });

  final TransitRouteDetail detail;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 190,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.navy.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.route,
                  size: 18,
                  color: isSelected ? AppColors.navy : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    detail.route.nameAr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${detail.stops.length} نقاط دلالة',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
