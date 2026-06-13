import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/transit_models.dart';
import '../../shared/widgets/route_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? activeRouteId = sampleRoute.id;

  @override
  Widget build(BuildContext context) {
    final routes = [
      sampleRoute,
      const TransitRoute(
        id: 'mansour',
        nameAr: 'الباب الشرقي - المنصور',
        routeType: RouteType.kia,
        status: RouteStatus.active,
        fareMin: 500,
        fareMax: 1000,
        operatingHoursStart: '٦:٣٠ ص',
        operatingHoursEnd: '١١:٠٠ م',
        confidenceScore: 82,
        lastVerifiedAt: null,
      ),
    ];
    TransitRoute? activeRoute;
    for (final route in routes) {
      if (route.id == activeRouteId) activeRoute = route;
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title:
              const Text('كيات', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
                onPressed: () => context.push('/auth'),
                icon: const Icon(Icons.person_outline))
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
          child: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (activeRoute case final activeRoute?) ...[
                    _ActiveRouteBanner(
                      route: activeRoute,
                      onOpen: () => context.push('/routes/${activeRoute.id}'),
                      onCancel: () => setState(() => activeRouteId = null),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(child: _SearchField(label: 'من وين؟')),
                      const SizedBox(width: 10),
                      Expanded(child: _SearchField(label: 'لوين؟')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...routes.map((route) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RouteCard(
                          route: route,
                          isActiveWait: route.id == activeRouteId,
                          disabled: activeRouteId != null &&
                              route.id != activeRouteId,
                        ),
                      )),
                  const SizedBox(height: 80),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RouteCard(route: sampleRoute),
                  const SizedBox(height: 80)
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search), hintText: label),
    );
  }
}
