import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/transit_repository.dart';
import '../../shared/ui/kiyat_logo.dart';
import '../../shared/widgets/route_card.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedIdsAsync = ref.watch(savedRouteIdsProvider);
    final routesAsync = ref.watch(routesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KiyatLogo(size: 30, showWordmark: false),
            SizedBox(width: 8),
            Text(
              'الخطوط المحفوظة',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: savedIdsAsync.when(
        data: (savedIds) {
          if (savedIds.isEmpty) {
            return _buildEmptyState();
          }
          return routesAsync.when(
            data: (routes) {
              final savedRoutes =
                  routes.where((r) => savedIds.contains(r.id)).toList();
              if (savedRoutes.isEmpty) {
                return _buildEmptyState();
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: savedRoutes.length,
                itemBuilder: (context, index) {
                  return RouteCard(route: savedRoutes[index]);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => _buildErrorState(ref),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => _buildErrorState(ref),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'لا توجد خطوط محفوظة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Tajawal',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'احفظ خطوطك المفضلة للوصول إليها بسرعة.',
              style: TextStyle(
                color: Colors.grey,
                fontFamily: 'Tajawal',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'حدث خطأ أثناء تحميل المحفوظات',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              ref.invalidate(savedRouteIdsProvider);
              ref.invalidate(routesProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة',
                style: TextStyle(fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
  }
}
