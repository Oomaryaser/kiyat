import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_utils/shared_utils.dart';

import '../../driver_repository.dart';
import '../../shared/widgets/slide_to_toggle.dart';
import 'driver_route_guidance.dart';
import 'tracking_map.dart';
import 'tracking_provider.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  static const double _routeSnapThresholdMeters = 35;
  bool stopping = false;

  @override
  Widget build(BuildContext context) {
    final trackingState = ref.watch(driverTrackingProvider);
    final routeGuidance = _getRouteGuidance(trackingState);
    final nearestWait = _getNearestWait(trackingState);

    return PopScope(
      canPop: !trackingState.isTracking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop(ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(trackingState.route?.nameAr ?? 'التتبع'),
          automaticallyImplyLeading: !trackingState.isTracking,
        ),
        body: Column(
          children: [
            Expanded(
              child: DriverTrackingMap(
                stops: trackingState.routeDetail?.stops ?? const [],
                waits: trackingState.waits,
                lastPosition: trackingState.lastPosition,
                routeName: trackingState.route?.nameAr ?? '',
                routeSnapThresholdMeters: _routeSnapThresholdMeters,
              ),
            ),
            _DriverNavigationSheet(
              routeName: trackingState.route?.nameAr ?? '',
              plateNumber: trackingState.vehicle?.plateNumber ?? 'كية',
              tracking: trackingState.isTracking,
              serverTrackingActive: trackingState.isServerTrackingActive,
              routeGuidance: routeGuidance,
              stopping: stopping,
              statusMessage: trackingState.statusMessage,
              waits: trackingState.waits,
              nearestWait: nearestWait,
              lastPosition: trackingState.lastPosition,
              onStop: () => _confirmStop(ref),
              isSimulating: trackingState.isSimulating,
              onStartSimulation: () => ref.read(driverTrackingProvider.notifier).startSimulationToNearestPassenger(),
              onStopSimulation: () => ref.read(driverTrackingProvider.notifier).stopSimulation(),
            ),
          ],
        ),
      ),
    );
  }

  PassengerWaitPoint? _getNearestWait(DriverTrackingState state) {
    if (state.waits.isEmpty) return null;
    final sorted = [...state.waits];
    sorted.sort((a, b) {
      final distanceA = _distanceToWait(state.lastPosition, a) ?? 0;
      final distanceB = _distanceToWait(state.lastPosition, b) ?? 0;
      return distanceA.compareTo(distanceB);
    });
    return sorted.first;
  }

  double? _distanceToWait(Position? lastPosition, PassengerWaitPoint wait) {
    if (lastPosition == null) return null;
    return Geolocator.distanceBetween(
      lastPosition.latitude,
      lastPosition.longitude,
      wait.lat,
      wait.lng,
    );
  }

  DriverRouteGuidance? _getRouteGuidance(DriverTrackingState state) {
    final position = state.lastPosition;
    final stops = state.routeDetail?.stops ?? const [];
    if (position == null || stops.length < 2) return null;
    return DriverRouteGuidance.fromStops(
      stops: stops,
      position: LatLng(position.latitude, position.longitude),
      thresholdMeters: _routeSnapThresholdMeters,
    );
  }

  Future<void> _confirmStop(WidgetRef ref) async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إيقاف التتبع؟'),
        content: const Text('إذا توقف التتبع، الراكب ما راح يشوف كيتك لايف.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (shouldStop == true) {
      await _stopTracking(ref);
    }
  }

  Future<void> _stopTracking(WidgetRef ref) async {
    if (stopping) return;
    setState(() => stopping = true);
    try {
      await ref.read(driverTrackingProvider.notifier).stopTracking();
      if (!mounted) return;
      setState(() {
        stopping = false;
      });
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        stopping = false;
      });
    }
  }
}

class _DriverNavigationSheet extends StatelessWidget {
  const _DriverNavigationSheet({
    required this.routeName,
    required this.plateNumber,
    required this.tracking,
    required this.serverTrackingActive,
    required this.routeGuidance,
    required this.stopping,
    required this.statusMessage,
    required this.waits,
    required this.nearestWait,
    required this.lastPosition,
    required this.onStop,
    required this.isSimulating,
    required this.onStartSimulation,
    required this.onStopSimulation,
  });

  final String routeName;
  final String plateNumber;
  final bool tracking;
  final bool serverTrackingActive;
  final DriverRouteGuidance? routeGuidance;
  final bool stopping;
  final String? statusMessage;
  final List<PassengerWaitPoint> waits;
  final PassengerWaitPoint? nearestWait;
  final Position? lastPosition;
  final VoidCallback onStop;
  final bool isSimulating;
  final VoidCallback onStartSimulation;
  final VoidCallback onStopSimulation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final distance = nearestWait == null ? null : _distanceToWait(nearestWait!);
    final isOffRoute = routeGuidance?.isOffRoute == true;
    final hasPassenger = nearestWait != null && !isOffRoute;
    final leadingColor = isOffRoute
        ? Colors.orange.shade900
        : hasPassenger
            ? Colors.orange.shade900
            : colors.primary;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: hasPassenger
                        ? Colors.orange.shade100
                        : isOffRoute
                            ? Colors.orange.shade100
                            : colors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOffRoute
                        ? Icons.navigation
                        : hasPassenger
                            ? Icons.navigation
                            : Icons.sensors,
                    color: leadingColor,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOffRoute
                            ? 'روح لهنا'
                            : hasPassenger
                                ? 'روح لأقرب راكب'
                                : 'استمر على خطك',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOffRoute
                            ? 'يبعد ${_formatDistance(routeGuidance!.distanceMeters)} عن الخط، حتى يبدأ التتبع مالتك.'
                            : hasPassenger
                            ? distance == null
                                  ? 'الراكب ظاهر على الخريطة'
                                  : 'يبعد ${_formatDistance(distance)} عنك'
                            : 'ماكو ركاب منتظرين حالياً، راقب الخريطة.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${waits.length}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isOffRoute || hasPassenger
                        ? Colors.orange.shade900
                        : colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _NavigationChip(
                  icon: serverTrackingActive
                      ? Icons.sensors
                      : Icons.sensors_off_outlined,
                  label: serverTrackingActive
                      ? 'التتبع شغال'
                      : tracking
                          ? 'بانتظار الخط'
                          : 'التتبع متوقف',
                  color: serverTrackingActive
                      ? colors.primary
                      : tracking
                          ? Colors.orange.shade800
                          : colors.error,
                ),
                _NavigationChip(
                  icon: Icons.route_outlined,
                  label: routeName,
                  color: colors.primary,
                ),
                _NavigationChip(
                  icon: Icons.confirmation_number_outlined,
                  label: plateNumber,
                  color: Colors.grey.shade700,
                ),
              ],
            ),
            if (statusMessage != null && statusMessage!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                statusMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isSimulating ? onStopSimulation : onStartSimulation,
                icon: Icon(
                  isSimulating ? Icons.stop_rounded : Icons.directions_car_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  isSimulating ? 'إيقاف محاكاة القيادة' : 'محاكاة القيادة نحو الراكب',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSimulating ? Colors.red.shade700 : colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SlideToToggle(
              onTriggered: onStop,
              label: stopping ? 'جاري إيقاف التتبع...' : 'اسحب لإيقاف التتبع ◀◀',
              enabled: !stopping,
            ),
          ],
        ),
      ),
    );
  }

  double? _distanceToWait(PassengerWaitPoint wait) {
    final pos = lastPosition;
    if (pos == null) return null;
    return Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      wait.lat,
      wait.lng,
    );
  }
}

class _NavigationChip extends StatelessWidget {
  const _NavigationChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${toArabicDigits(meters.round())} م';
  return '${toArabicDigits((meters / 1000).toStringAsFixed(1))} كم';
}
