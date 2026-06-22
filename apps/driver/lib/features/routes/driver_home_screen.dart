import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_utils/shared_utils.dart';

import '../../driver_repository.dart';
import '../../shared/widgets/state_panel.dart';
import '../settings/driver_settings_screen.dart';
import '../tracking/tracking_screen.dart';
import '../tracking/tracking_provider.dart';
import 'routes_provider.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.session,
  });

  final DriverSession session;

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final plateController = TextEditingController(text: 'كية');
  bool starting = false;
  String? error;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedPlateNumber();
  }

  @override
  void dispose() {
    plateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? 'كيات السائق'
              : _currentIndex == 1
                  ? 'أرباح اليوم والعداد'
                  : 'الإعدادات',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildRoutesTab(),
          _buildEarningsTab(),
          DriverSettingsTab(
            plateController: plateController,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'الخطوط',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate_outlined),
            activeIcon: Icon(Icons.calculate),
            label: 'الأرباح والعداد',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }

  Widget _buildRoutesTab() {
    final routesAsync = ref.watch(driverRoutesProvider);
    final selectedRoute = ref.watch(selectedRouteProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(onRefresh: _refreshRoutes),
          const SizedBox(height: 14),
          routesAsync.when(
            data: (routes) {
              if (routes.isEmpty) {
                return StatePanel(
                  icon: Icons.route_outlined,
                  title: 'ماكو خطوط حالياً',
                  message: 'شغل seed البيانات أو أضف خطوط من لوحة السيرفر.',
                  action: FilledButton.icon(
                    onPressed: _refreshRoutes,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث'),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اختار خطك للبدء',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ...routes.map(
                    (route) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RouteChoiceCard(
                        route: route,
                        selected: selectedRoute?.id == route.id,
                        onTap: () {
                          ref.read(selectedRouteProvider.notifier).select(route);
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => StatePanel(
              icon: Icons.wifi_off_outlined,
              title: 'ما قدرنا نجيب الخطوط',
              message: 'تأكد من تشغيل الباكند والاتصال.',
              action: FilledButton.icon(
                onPressed: _refreshRoutes,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            StatePanel(
              icon: Icons.error_outline,
              title: 'صار خطأ',
              message: error!,
            ),
          ],
          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: selectedRoute == null || starting
                ? null
                : _startTracking,
            icon: starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(starting ? 'دا نبدي...' : 'بدء التتبع والعمل المباشر'),
          ),
        ),
      ),
    );
  }

  Widget _buildEarningsTab() {
    final colors = Theme.of(context).colorScheme;
    final selectedRoute = ref.watch(selectedRouteProvider);
    final passengerCount = ref.watch(passengerCountProvider);

    final fare = selectedRoute != null ? selectedRoute.fareMin : 1000;
    final estimatedTotal = passengerCount * fare;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primary, colors.primary.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text(
                'إجمالي الأرباح التقديرية اليوم',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatAmount(estimatedTotal)} د.ع',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'محسوبة على أساس تعرفة ${selectedRoute != null ? selectedRoute.nameAr : "خط افتراضي"} (${_formatAmount(fare)} د.ع للراكب)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'عداد الركاب اليومي',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('اضغط لتسجيل الركاب الذين صعدوا معك:'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filledTonal(
                      onPressed: passengerCount > 0
                          ? () => ref.read(passengerCountProvider.notifier).decrement()
                          : null,
                      icon: const Icon(Icons.remove, size: 28),
                    ),
                    Text(
                      '$passengerCount',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () => ref.read(passengerCountProvider.notifier).increment(),
                      icon: const Icon(Icons.add, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('تصفير العداد؟'),
                        content: const Text('هل أنت متأكد من تصفير عداد الركاب اليوم؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('تصفير'),
                          ),
                        ],
                      ),
                    ).then((value) {
                      if (value == true) {
                        ref.read(passengerCountProvider.notifier).reset();
                      }
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('تصفير العداد لليوم الجديد'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade900),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'أرباح كيات التقديرية تُحسب لمساعدتك فقط. الدفع الحقيقي يتم نقداً من الركاب أثناء الرحلة.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7F5F00)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatAmount(int amt) {
    return toArabicDigits(amt.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        ));
  }

  void _refreshRoutes() {
    ref.invalidate(driverRoutesProvider);
    setState(() {
      error = null;
    });
  }

  Future<void> _loadSavedPlateNumber() async {
    final plate = await ref.read(driverRepositoryProvider).loadPlateNumber();
    if (!mounted) return;
    plateController.text = plate;
  }

  Future<void> _startTracking() async {
    final route = ref.read(selectedRouteProvider);
    if (route == null) return;
    setState(() {
      starting = true;
      error = null;
    });
    try {
      final plate = plateController.text.trim().isEmpty
          ? 'كية'
          : plateController.text.trim();
      
      await ref.read(driverTrackingProvider.notifier).startTracking(route, plate);
      
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TrackingScreen(),
        ),
      );
    } on DriverRepositoryException catch (exception) {
      setState(() => error = exception.message);
    } catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_bus_filled,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تطبيق السائق',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'اختار خطك وشغل التتبع حتى الركاب يشوفون كيتك.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث الخطوط',
          ),
        ],
      ),
    );
  }
}

class _RouteChoiceCard extends StatelessWidget {
  const _RouteChoiceCard({
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final DriverRoute route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: selected ? colors.primary.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.route_outlined,
          color: colors.primary,
        ),
        title: Text(
          route.nameAr,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _RouteChip(icon: Icons.payments_outlined, label: route.fareLabel),
              _RouteChip(
                icon: Icons.schedule_outlined,
                label: route.hoursLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade700),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade800)),
      ],
    );
  }
}
