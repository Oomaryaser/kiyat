import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/data/transit_repository.dart';
import '../../shared/ui/kiyat_logo.dart';
import '../../shared/settings/passenger_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(passengerSettingsProvider);
    final controller = ref.watch(passengerSettingsControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(child: KiyatLogo(size: 56)),
          const SizedBox(height: 16),
          settingsAsync.when(
            data: (settings) => _SettingsSection(
              children: [
                SwitchListTile(
                  value: settings.arrivalAlertsEnabled,
                  onChanged: controller.setArrivalAlertsEnabled,
                  title: const Text('تنبيهات اقتراب الكية'),
                  subtitle: const Text('ننبهك داخل التطبيق إذا بقى دقيقتين.'),
                  secondary: const Icon(Icons.notifications_active_outlined),
                ),
                SwitchListTile(
                  value: settings.autoOpenActiveWait,
                  onChanged: controller.setAutoOpenActiveWait,
                  title: const Text('فتح الانتظار الحالي تلقائياً'),
                  subtitle: const Text(
                      'إذا عندك خط تنتظره، افتحه مباشرة عند الدخول.'),
                  secondary: const Icon(Icons.near_me_outlined),
                ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            children: [
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('مظهر التطبيق'),
                subtitle: Text(switch (themeMode) {
                  ThemeMode.system => 'تلقائي حسب الجهاز',
                  ThemeMode.light => 'فاتح',
                  ThemeMode.dark => 'داكن',
                }),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _showThemeDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            children: [
              ListTile(
                leading: const Icon(Icons.my_location_outlined),
                title: const Text('إعدادات الموقع'),
                subtitle: const Text('فعل الموقع حتى نحسب أقرب كية بدقة.'),
                trailing: const Icon(Icons.chevron_left),
                onTap: Geolocator.openAppSettings,
              ),
              ListTile(
                leading: const Icon(Icons.location_searching_outlined),
                title: const Text('خدمة الموقع بالجهاز'),
                subtitle: const Text('افتح إعدادات GPS إذا كانت مطفية.'),
                trailing: const Icon(Icons.chevron_left),
                onTap: Geolocator.openLocationSettings,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            children: [
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('مسح الانتظار الحالي'),
                subtitle: const Text('يلغي ظهورك كراكب منتظر على الخط.'),
                onTap: () => _clearWait(context, ref),
              ),
              ListTile(
                leading: const KiyatLogo(size: 34, showWordmark: false),
                title: const Text('كيات'),
                subtitle: const Text('نسخة الراكب التجريبية لبغداد.'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مظهر التطبيق'),
        content: RadioGroup<ThemeMode>(
          groupValue: ref.watch(themeModeProvider),
          onChanged: (mode) {
            if (mode == null) return;
            ref.read(themeModeProvider.notifier).setThemeMode(mode);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('تلقائي حسب الجهاز'),
                leading: const Radio<ThemeMode>(value: ThemeMode.system),
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.system);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('فاتح'),
                leading: const Radio<ThemeMode>(value: ThemeMode.light),
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.light);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('داكن'),
                leading: const Radio<ThemeMode>(value: ThemeMode.dark),
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.dark);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearWait(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(transitRepositoryProvider);
    final waitId = await repository.loadActiveWaitSessionId();
    if (waitId != null && waitId.isNotEmpty) {
      await repository.cancelPassengerWait(waitId);
    }
    await repository.clearActiveWaitRouteId();
    ref.invalidate(activeWaitRouteIdProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح الانتظار الحالي.')),
    );
    context.go('/');
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardTheme.color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(children: children),
    );
  }
}
