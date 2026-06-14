import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../shared/data/transit_repository.dart';
import '../../shared/models/transit_models.dart';
import '../../shared/settings/passenger_settings.dart';
import '../../shared/ui/app_state_message.dart';
import '../../shared/widgets/route_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? activeRouteId;
  bool waitingEnabled = true;
  String searchQuery = '';
  bool autoOpenedActiveWait = false;
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
    final settings = ref.watch(passengerSettingsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final savedRouteIds = ref.watch(savedRouteIdsProvider).maybeWhen(
          data: (ids) => ids,
          orElse: () => const <String>{},
        );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title:
              const Text('كيات', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'الإعدادات',
            ),
          ],
          bottom: const TabBar(
              tabs: [Tab(text: 'الخطوط القريبة'), Tab(text: 'المحفوظة')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/map'),
          icon: const Icon(Icons.map_outlined),
          label: const Text('عرض الخريطة'),
        ),
        body: SafeArea(
          child: detailsAsync.when(
            data: (details) {
              final activeId = _effectiveActiveRouteId(
                details.map((detail) => detail.route).toList(),
                savedActiveRouteId,
              );
              if (settings?.autoOpenActiveWait == true &&
                  activeId != null &&
                  !autoOpenedActiveWait) {
                autoOpenedActiveWait = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  context.push('/routes/$activeId');
                });
              }
              return _HomeTabs(
                details: details,
                activeRouteId: activeId,
                waitingEnabled: waitingEnabled,
                searchQuery: searchQuery,
                currentPosition: currentPosition,
                locationMessage: locationMessage,
                usingFallbackData:
                    details.any((detail) => detail.route.id == sampleRoute.id),
                savedRouteIds: savedRouteIds,
                onSearchChanged: (value) => setState(() => searchQuery = value),
                onUseCurrentLocation: _loadCurrentPosition,
                onCancelWait: _cancelWait,
                onRefresh: _refreshHome,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _HomeTabs(
              details: const [
                TransitRouteDetail(route: sampleRoute, stops: sampleStops)
              ],
              activeRouteId: sampleRoute.id,
              waitingEnabled: waitingEnabled,
              searchQuery: searchQuery,
              currentPosition: currentPosition,
              locationMessage:
                  'ما قدرنا نتصل بالخادم، نعرض بيانات محفوظة مؤقتاً.',
              usingFallbackData: true,
              savedRouteIds: savedRouteIds,
              onSearchChanged: (value) => setState(() => searchQuery = value),
              onUseCurrentLocation: _loadCurrentPosition,
              onCancelWait: _cancelWait,
              onRefresh: _refreshHome,
            ),
          ),
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

  void _cancelWait() async {
    final repository = ref.read(transitRepositoryProvider);
    final waitId = await repository.loadActiveWaitSessionId();
    if (waitId != null && waitId.isNotEmpty) {
      await repository.cancelPassengerWait(waitId);
    }
    await repository.clearActiveWaitRouteId();
    ref.invalidate(activeWaitRouteIdProvider);
    setState(() {
      activeRouteId = null;
      waitingEnabled = false;
    });
  }

  Future<void> _refreshHome() async {
    ref.invalidate(routeDetailsProvider);
    ref.invalidate(activeWaitRouteIdProvider);
    await _loadCurrentPosition();
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
      final position = await Geolocator.getCurrentPosition(
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

class _HomeTabs extends StatelessWidget {
  const _HomeTabs({
    required this.details,
    required this.activeRouteId,
    required this.waitingEnabled,
    required this.searchQuery,
    required this.currentPosition,
    required this.locationMessage,
    required this.usingFallbackData,
    required this.savedRouteIds,
    required this.onSearchChanged,
    required this.onUseCurrentLocation,
    required this.onCancelWait,
    required this.onRefresh,
  });

  final List<TransitRouteDetail> details;
  final String? activeRouteId;
  final bool waitingEnabled;
  final String searchQuery;
  final Position? currentPosition;
  final String? locationMessage;
  final bool usingFallbackData;
  final Set<String> savedRouteIds;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onCancelWait;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    TransitRoute? activeRoute;
    for (final detail in details) {
      if (detail.route.id == activeRouteId) activeRoute = detail.route;
    }
    final sortedDetails = _sortedAndFilteredDetails;

    return TabBarView(
      children: [
        RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (activeRoute case final activeRoute?) ...[
                _ActiveRouteBanner(
                  route: activeRoute,
                  onOpen: () => context.push('/routes/${activeRoute.id}'),
                  onCancel: onCancelWait,
                ),
                const SizedBox(height: 14),
              ],
              _LocationModeBanner(
                onOpenMap: () => context.push('/map'),
                onUseCurrentLocation: onUseCurrentLocation,
                locationMessage: locationMessage,
                hasLocation: currentPosition != null,
              ),
              const SizedBox(height: 16),
              if (usingFallbackData) ...[
                AppStateMessage(
                  icon: Icons.wifi_off_outlined,
                  title: 'الاتصال مو ثابت',
                  message: 'نعرض بيانات مؤقتة إلى أن يرجع الاتصال بالخادم.',
                  action: TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _RouteSearchField(
                value: searchQuery,
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: 12),
              if (sortedDetails.isEmpty)
                AppStateMessage(
                  icon: Icons.search_off,
                  title: 'ما لقينا خط بهذا الاسم',
                  message:
                      'جرّب تكتب منطقة ثانية مثل الكاظمية أو الباب الشرقي.',
                  action: TextButton.icon(
                    onPressed: () => onSearchChanged(''),
                    icon: const Icon(Icons.close),
                    label: const Text('مسح البحث'),
                  ),
                )
              else
                ...sortedDetails.map((detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RouteCard(
                        route: detail.route,
                        distanceMeters: _distanceToRoute(detail),
                        isActiveWait: detail.route.id == activeRouteId,
                        disabled: activeRouteId != null &&
                            detail.route.id != activeRouteId,
                      ),
                    )),
              const SizedBox(height: 80),
            ],
          ),
        ),
        Builder(builder: (context) {
          final savedDetails = details
              .where((detail) => savedRouteIds.contains(detail.route.id))
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (activeRoute != null) RouteCard(route: activeRoute),
              if (savedDetails.isNotEmpty) ...[
                if (activeRoute != null) const SizedBox(height: 12),
                ...savedDetails.map(
                  (detail) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RouteCard(route: detail.route),
                  ),
                ),
              ],
              if (activeRoute == null && savedDetails.isEmpty)
                const AppStateMessage(
                  icon: Icons.bookmark_border,
                  title: 'ماكو خط محفوظ حالياً',
                  message: 'افتح أي خط واضغط علامة الحفظ حتى يظهر هنا.',
                ),
              const SizedBox(height: 80),
            ],
          );
        }),
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
}

class _ActiveRouteBanner extends StatelessWidget {
  const _ActiveRouteBanner({
    required this.route,
    required this.onOpen,
    required this.onCancel,
  });

  final TransitRoute route;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('أنت حالياً تنتظر هذا الخط',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(route.nameAr,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('راح نركز على أقرب كية جاية لك ونوقف باقي الخطوط مؤقتاً.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.92))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.directions_bus_filled),
                  label: const Text('افتح التتبع'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onCancel,
                icon: const Icon(Icons.close),
                tooltip: 'إلغاء الانتظار',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationModeBanner extends StatelessWidget {
  const _LocationModeBanner({
    required this.onOpenMap,
    required this.onUseCurrentLocation,
    required this.locationMessage,
    required this.hasLocation,
  });

  final VoidCallback onOpenMap;
  final VoidCallback onUseCurrentLocation;
  final String? locationMessage;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.my_location, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    hasLocation
                        ? 'موقعك الحالي هو نقطة البداية'
                        : 'رتب الخطوط حسب موقعك',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(locationMessage ??
                    'اختار خط، واحنا نحسب أقرب كية عليك تلقائياً.'),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onUseCurrentLocation,
            icon: const Icon(Icons.near_me_outlined),
            tooltip: 'استخدام موقعي',
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            onPressed: onOpenMap,
            icon: const Icon(Icons.map_outlined),
            tooltip: 'عرض الخريطة',
          ),
        ],
      ),
    );
  }
}

class _RouteSearchField extends StatelessWidget {
  const _RouteSearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        suffixIcon: value.isEmpty
            ? null
            : IconButton(
                onPressed: () => onChanged(''),
                icon: const Icon(Icons.close),
                tooltip: 'مسح البحث',
              ),
        hintText: 'ابحث عن خط أو منطقة',
      ),
    );
  }
}
