import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/transit_models.dart';
import '../../shared/widgets/live_route_map.dart';
import '../report/report_bottom_sheet.dart';

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({super.key, required this.routeId});

  final String routeId;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  bool saved = false;
  int? pickupStopIndex;
  bool usingCurrentLocation = true;
  bool locating = true;
  String? locationError;

  TransitStop? get pickupStop =>
      pickupStopIndex == null ? null : sampleStops[pickupStopIndex!];

  VehicleArrivalEstimate? get selectedArrival {
    if (!usingCurrentLocation && pickupStopIndex == null) return null;
    final upcoming =
        sampleVehicles.where((vehicle) => !vehicle.hasPassedPickup).toList();
    if (upcoming.isNotEmpty) return upcoming.first;
    return sampleVehicles.isEmpty ? null : sampleVehicles.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrentLocation());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final arrival = selectedArrival;

    return Scaffold(
      appBar: AppBar(
        title: const Text('انتظار الخط'),
        actions: [
          IconButton(
            onPressed: () => setState(() => saved = !saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            tooltip: saved ? 'محفوظ' : 'حفظ الخط',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WaitingHeader(
            route: sampleRoute,
            arrival: arrival,
            pickupStop: pickupStop,
            locating: locating,
            hasLocationError: locationError != null,
          ),
          const SizedBox(height: 12),
          _ArrivalCard(
            pickupStop: pickupStop,
            usingCurrentLocation: usingCurrentLocation,
            locating: locating,
            locationError: locationError,
            arrival: selectedArrival,
            nearbyVehicles: sampleVehicles,
            skippedCount: sampleVehicles
                .where((vehicle) => vehicle.hasPassedPickup)
                .length,
            onUseCurrentLocation: _useCurrentLocation,
            onSelectPickup: _showPickupSelector,
          ),
          const SizedBox(height: 16),
          _RouteSummary(route: sampleRoute),
          const SizedBox(height: 12),
          _LandmarkStrip(
            stops: sampleStops,
            pickupStop: pickupStop,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const ReportBottomSheet(routeId: 'sample'),
            ),
            icon: Icon(Icons.report_outlined, color: colors.error),
            label: const Text('بلّغ عن تغيير بالخط'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showPickupSelector() {
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
              ...sampleStops.indexed.map(
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
                      locationError = null;
                    });
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

  Future<void> _useCurrentLocation() async {
    if (!mounted) return;
    setState(() {
      locating = true;
      locationError = null;
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
        throw const PermissionDeniedException('Location permission denied');
      }

      final position = await Geolocator.getCurrentPosition();
      final nearestIndex =
          _nearestStopIndex(position.latitude, position.longitude);
      setState(() {
        pickupStopIndex = nearestIndex;
        usingCurrentLocation = true;
      });
    } catch (_) {
      setState(() {
        locationError =
            'ما قدرنا نحدد موقعك. تأكد من صلاحية الموقع أو اختار مكانك يدوياً.';
      });
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  int _nearestStopIndex(double lat, double lng) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (final item in sampleStops.indexed) {
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
    required this.arrival,
    required this.nearbyVehicles,
    required this.skippedCount,
    required this.onUseCurrentLocation,
    required this.onSelectPickup,
  });

  final TransitStop? pickupStop;
  final bool usingCurrentLocation;
  final bool locating;
  final String? locationError;
  final VehicleArrivalEstimate? arrival;
  final List<VehicleArrivalEstimate> nearbyVehicles;
  final int skippedCount;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onSelectPickup;

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

    if (arrival == null) {
      return _InfoTile(
        icon: Icons.sensors_off_outlined,
        title: 'ماكو تتبع حي حالياً',
        subtitle: usingCurrentLocation
            ? 'موقعك الحالي قرب ${pickupStop!.nameAr}. راح نعرض أقرب كية أول ما تظهر على نفس الاتجاه.'
            : 'مكان صعودك قرب ${pickupStop!.nameAr}. راح نعرض أقرب كية أول ما تظهر على نفس الاتجاه.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary.withValues(alpha: 0.18))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 230,
            child: LiveRouteMap(
              stops: sampleStops,
              vehicles: nearbyVehicles,
              pickupStop: pickupStop,
              selectedVehicle: arrival,
              compact: true,
            ),
          ),
          const SizedBox(height: 12),
          _StatusLine(
            icon: Icons.place_outlined,
            label: usingCurrentLocation ? 'موقعك' : 'مكان الصعود',
            value: 'قرب ${pickupStop!.nameAr}',
          ),
          const SizedBox(height: 8),
          _StatusLine(
            icon: Icons.directions_bus_filled,
            label: 'أقرب كية',
            value:
                '${arrival!.vehicleLabel} قرب ${arrival!.nearStopName}، تبعد ${arrival!.distanceMeters} م',
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: locating ? null : onUseCurrentLocation,
                  icon: const Icon(Icons.near_me_outlined),
                  label: const Text('إعادة تحديد موقعي'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: onSelectPickup,
                icon: const Icon(Icons.edit_location_alt_outlined),
                tooltip: 'اختيار يدوي',
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => context.push('/map'),
                icon: const Icon(Icons.map_outlined),
                tooltip: 'الخريطة الكاملة',
              ),
            ],
          ),
        ],
      ),
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
  });

  final TransitRoute route;
  final VehicleArrivalEstimate? arrival;
  final TransitStop? pickupStop;
  final bool locating;
  final bool hasLocationError;

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
    final etaLabel = locating
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
