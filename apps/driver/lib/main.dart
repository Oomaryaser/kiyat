import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'driver_repository.dart';

void main() {
  runApp(const ProviderScope(child: KiyatDriverApp()));
}

class KiyatDriverApp extends ConsumerWidget {
  const KiyatDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'كيات السائق',
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [Locale('ar', 'IQ'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const DriverAuthGate(),
    );
  }
}

class DriverAuthGate extends StatefulWidget {
  const DriverAuthGate({super.key});

  @override
  State<DriverAuthGate> createState() => _DriverAuthGateState();
}

class _DriverAuthGateState extends State<DriverAuthGate> {
  final repository = DriverRepository();
  late Future<DriverSession?> sessionFuture;
  DriverSession? session;

  @override
  void initState() {
    super.initState();
    sessionFuture = repository.loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DriverSession?>(
      future: sessionFuture,
      builder: (context, snapshot) {
        final activeSession = session ?? snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            activeSession == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (activeSession == null) {
          return DriverAuthScreen(
            repository: repository,
            onSignedIn: (nextSession) => setState(() => session = nextSession),
          );
        }
        return DriverHomeScreen(
          repository: repository,
          session: activeSession,
          onSignOut: () async {
            await repository.signOut();
            if (!mounted) return;
            setState(() {
              session = null;
              sessionFuture = Future.value(null);
            });
          },
        );
      },
    );
  }
}

class DriverAuthScreen extends StatefulWidget {
  const DriverAuthScreen({
    super.key,
    required this.repository,
    required this.onSignedIn,
  });

  final DriverRepository repository;
  final ValueChanged<DriverSession> onSignedIn;

  @override
  State<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends State<DriverAuthScreen> {
  final PageController _pageController = PageController();
  final phoneController = TextEditingController(text: '+964');
  
  // OTP variables
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  int _step = 0; // 0: Phone, 1: OTP
  bool loading = false;
  String? error;
  
  // Resend OTP Timer
  Timer? _resendTimer;
  int _resendSeconds = 60;
  bool _canResend = false;

  @override
  void dispose() {
    _pageController.dispose();
    phoneController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = 60;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        setState(() {
          _canResend = true;
          _resendTimer?.cancel();
        });
      }
    });
  }

  String _cleanPhoneNumber(String raw) {
    var phone = raw.trim();
    if (phone.startsWith('07')) {
      phone = '+964${phone.substring(1)}';
    } else if (phone.startsWith('7')) {
      phone = '+964$phone';
    }
    return phone;
  }

  bool _validatePhone(String phone) {
    final clean = _cleanPhoneNumber(phone);
    return clean.startsWith('+9647') && clean.length == 13;
  }

  Future<void> _sendOtp() async {
    final phone = phoneController.text.trim();
    if (!_validatePhone(phone)) {
      setState(() => error = 'الرجاء إدخال رقم هاتف عراقي صحيح (مثال: 07701234567).');
      HapticFeedback.vibrate();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cleanPhone = _cleanPhoneNumber(phone);
      await widget.repository.sendOtp(cleanPhone);
      HapticFeedback.mediumImpact();
      _startResendTimer();
      setState(() {
        _step = 1;
        loading = false;
      });
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _otpFocusNodes[0].requestFocus();
        }
      });
    } on DriverRepositoryException catch (exception) {
      setState(() {
        error = exception.message;
        loading = false;
      });
      HapticFeedback.vibrate();
    } catch (_) {
      setState(() {
        error = 'تعذر إرسال الرمز. يرجى المحاولة لاحقاً.';
        loading = false;
      });
      HapticFeedback.vibrate();
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _cleanPhoneNumber(phoneController.text);
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      setState(() => error = 'الرجاء إدخال رمز التحقق المكون من 6 أرقام.');
      HapticFeedback.vibrate();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await widget.repository.verifyDriverOtp(
        phone: phone,
        otp: otp,
      );
      HapticFeedback.mediumImpact();
      widget.onSignedIn(session);
    } on DriverRepositoryException catch (exception) {
      setState(() {
        error = exception.message;
        loading = false;
      });
      HapticFeedback.vibrate();
    } catch (_) {
      setState(() {
        error = 'رمز التحقق غير صحيح أو منتهي الصلاحية.';
        loading = false;
      });
      HapticFeedback.vibrate();
    }
  }

  Future<void> _devLogin() async {
    var phone = phoneController.text.trim();
    if (!_validatePhone(phone)) {
      phone = '07701234567';
      phoneController.text = phone;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cleanPhone = _cleanPhoneNumber(phone);
      final session = await widget.repository.devDriverLogin(phone: cleanPhone);
      HapticFeedback.mediumImpact();
      widget.onSignedIn(session);
    } on DriverRepositoryException catch (exception) {
      setState(() {
        error = exception.message;
        loading = false;
      });
      HapticFeedback.vibrate();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _step == 0 ? 'تسجيل دخول السائق' : 'رمز التحقق',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _step = 0;
                    error = null;
                  });
                  _pageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              )
            : null,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildPhoneStep(),
          _buildOtpStep(),
        ],
      ),
    );
  }

  Widget _buildPhoneStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _LoginHeroPanel(),
        const SizedBox(height: 24),
        Text(
          'أدخل رقم الهاتف للبدء',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            hintText: '0770 123 4567',
            prefixIcon: Icon(Icons.phone_iphone_outlined),
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _sendOtp(),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          _StatePanel(
            icon: Icons.error_outline,
            title: 'خطأ',
            message: error!,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: loading ? null : _sendOtp,
          icon: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.arrow_forward),
          label: const Text('إرسال رمز التأكيد (OTP)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: loading ? null : _devLogin,
          icon: const Icon(Icons.login),
          label: const Text('دخول سريع (تجريبي 123456)'),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'أدخل الرمز المكون من 6 أرقام المرسل إلى الرقم:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          phoneController.text.trim(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    if (index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    } else {
                      _otpFocusNodes[index].unfocus();
                      _verifyOtp(); // Auto submit
                    }
                  } else {
                    if (index > 0) {
                      _otpFocusNodes[index - 1].requestFocus();
                    }
                  }
                },
              ),
            );
          }),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          _StatePanel(
            icon: Icons.error_outline,
            title: 'تعذر التحقق',
            message: error!,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: loading ? null : _verifyOtp,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('تأكيد الرمز والدخول'),
        ),
        const SizedBox(height: 16),
        Center(
          child: _canResend
              ? TextButton(
                  onPressed: _sendOtp,
                  child: const Text('إعادة إرسال الرمز'),
                )
              : Text(
                  'يمكنك إعادة الإرسال خلال $_resendSeconds ثانية',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
        ),
      ],
    );
  }
}

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.repository,
    required this.session,
    required this.onSignOut,
  });

  final DriverRepository repository;
  final DriverSession session;
  final Future<void> Function() onSignOut;

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final plateController = TextEditingController(text: 'كية');
  late Future<List<DriverRoute>> routesFuture;
  DriverRoute? selectedRoute;
  bool starting = false;
  String? error;

  int _currentIndex = 0;
  int _passengerCount = 0;

  @override
  void initState() {
    super.initState();
    routesFuture = widget.repository.listRoutes();
    _loadSavedPlateNumber();
    _loadPassengerCount();
  }

  @override
  void dispose() {
    plateController.dispose();
    super.dispose();
  }

  Future<void> _loadPassengerCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _passengerCount = prefs.getInt('driver_passenger_count') ?? 0;
    });
  }

  Future<void> _savePassengerCount(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('driver_passenger_count', val);
    setState(() {
      _passengerCount = val;
    });
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
          _buildSettingsTab(),
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
    return FutureBuilder<List<DriverRoute>>(
      future: routesFuture,
      builder: (context, snapshot) {
        final routes = snapshot.data ?? const <DriverRoute>[];
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroPanel(onRefresh: _refreshRoutes),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                _StatePanel(
                  icon: Icons.wifi_off_outlined,
                  title: 'ما قدرنا نجيب الخطوط',
                  message: 'تأكد من تشغيل الباكند والاتصال.',
                  action: FilledButton.icon(
                    onPressed: _refreshRoutes,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                )
              else ...[
                if (routes.isEmpty)
                  _StatePanel(
                    icon: Icons.route_outlined,
                    title: 'ماكو خطوط حالياً',
                    message: 'شغل seed البيانات أو أضف خطوط من لوحة السيرفر.',
                    action: FilledButton.icon(
                      onPressed: _refreshRoutes,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تحديث'),
                    ),
                  )
                else ...[
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
                        onTap: () => setState(() => selectedRoute = route),
                      ),
                    ),
                  ),
                ],
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                _StatePanel(
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
      },
    );
  }

  Widget _buildEarningsTab() {
    final colors = Theme.of(context).colorScheme;
    final fare = selectedRoute != null ? selectedRoute!.fareMin : 1000;
    final estimatedTotal = _passengerCount * fare;

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
                'محسوبة على أساس تعرفة ${selectedRoute != null ? selectedRoute!.nameAr : "خط افتراضي"} (${_formatAmount(fare)} د.ع للراكب)',
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
                      onPressed: _passengerCount > 0
                          ? () => _savePassengerCount(_passengerCount - 1)
                          : null,
                      icon: const Icon(Icons.remove, size: 28),
                    ),
                    Text(
                      '${_passengerCount}',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () => _savePassengerCount(_passengerCount + 1),
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
                      if (value == true) _savePassengerCount(0);
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

  Widget _buildSettingsTab() {
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'معلومات المركبة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: plateController,
                  decoration: const InputDecoration(
                    labelText: 'رقم أو اسم الكية الحالي',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                  onChanged: (val) => widget.repository.savePlateNumber(val),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
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
                onTap: () => _showThemeDialog(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('رقم الهاتف المسجل'),
                subtitle: Text(widget.session.phone),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('الدعم والمساعدة'),
                subtitle: Text('للدعم الفني اتصل بنا: 0780 123 4567'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                title: Text(
                  'تسجيل الخروج',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تسجيل خروج؟'),
                      content: const Text('هل أنت متأكد من تسجيل الخروج من حساب السائق؟'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('خروج'),
                        ),
                      ],
                    ),
                  ).then((value) {
                    if (value == true) widget.onSignOut();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showThemeDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مظهر التطبيق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('تلقائي حسب الجهاز'),
              leading: Radio<ThemeMode>(
                value: ThemeMode.system,
                groupValue: ref.watch(themeModeProvider),
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    Navigator.pop(context);
                  }
                },
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('فاتح'),
              leading: Radio<ThemeMode>(
                value: ThemeMode.light,
                groupValue: ref.watch(themeModeProvider),
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    Navigator.pop(context);
                  }
                },
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('داكن'),
              leading: Radio<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: ref.watch(themeModeProvider),
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    Navigator.pop(context);
                  }
                },
              ),
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(int amt) {
    return _arabicDigits(amt.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        ));
  }

  void _refreshRoutes() {
    setState(() {
      routesFuture = widget.repository.listRoutes();
      error = null;
    });
  }

  Future<void> _loadSavedPlateNumber() async {
    final plate = await widget.repository.loadPlateNumber();
    if (!mounted) return;
    plateController.text = plate;
  }

  Future<void> _startTracking() async {
    final route = selectedRoute;
    if (route == null) return;
    setState(() {
      starting = true;
      error = null;
    });
    try {
      final vehicle = await widget.repository.createVehicle(
        routeId: route.id,
        plateNumber: plateController.text.trim().isEmpty
            ? 'كية'
            : plateController.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrackingScreen(
            route: route,
            vehicle: vehicle,
            repository: widget.repository,
          ),
        ),
      );
    } on DriverRepositoryException catch (exception) {
      setState(() => error = exception.message);
    } catch (_) {
      setState(() => error = 'ما قدرنا نسجل الكية على هذا الخط.');
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }
}

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({
    super.key,
    required this.route,
    required this.vehicle,
    required this.repository,
  });

  final DriverRoute route;
  final DriverVehicle vehicle;
  final DriverRepository repository;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  StreamSubscription<Position>? positionSubscription;
  Timer? waitsTimer;
  late Future<DriverRouteDetail> routeDetailFuture;
  List<PassengerWaitPoint> waits = const [];
  Position? lastPosition;
  bool tracking = false;
  bool stopping = false;
  String? statusMessage;

  @override
  void initState() {
    super.initState();
    routeDetailFuture = widget.repository.routeDetail(widget.route.id);
    _startLiveTracking();
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    waitsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nearestWait = _nearestWait;
    return PopScope(
      canPop: !tracking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.route.nameAr),
          automaticallyImplyLeading: !tracking,
        ),
        body: Column(
          children: [
            Expanded(
              child: FutureBuilder<DriverRouteDetail>(
                future: routeDetailFuture,
                builder: (context, snapshot) {
                  return _DriverTrackingMap(
                    stops: snapshot.data?.stops ?? const [],
                    waits: waits,
                    lastPosition: lastPosition,
                    routeName: widget.route.nameAr,
                  );
                },
              ),
            ),
            _DriverNavigationSheet(
              routeName: widget.route.nameAr,
              plateNumber: widget.vehicle.plateNumber,
              tracking: tracking,
              stopping: stopping,
              statusMessage: statusMessage,
              waits: waits,
              nearestWait: nearestWait,
              lastPosition: lastPosition,
              onStop: _confirmStop,
            ),
          ],
        ),
      ),
    );
  }

  PassengerWaitPoint? get _nearestWait {
    if (waits.isEmpty) return null;
    final sorted = [...waits];
    sorted.sort((a, b) {
      final distanceA = _distanceToWait(a) ?? 0;
      final distanceB = _distanceToWait(b) ?? 0;
      return distanceA.compareTo(distanceB);
    });
    return sorted.first;
  }

  double? _distanceToWait(PassengerWaitPoint wait) {
    final position = lastPosition;
    if (position == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      wait.lat,
      wait.lng,
    );
  }

  Future<void> _startLiveTracking() async {
    setState(() {
      tracking = true;
      statusMessage = 'دا نطلب صلاحية الموقع...';
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          tracking = false;
          statusMessage = 'خدمة الموقع مطفية. شغلها حتى تبدي التتبع.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          tracking = false;
          statusMessage = 'نحتاج صلاحية الموقع حتى يشوفك الراكب.';
        });
        return;
      }

      final firstPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _sendPosition(firstPosition);
      waitsTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _loadPassengerWaits(),
      );
      await _loadPassengerWaits();
      positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 18,
        ),
      ).listen(_sendPosition);
      setState(() => statusMessage = 'التتبع شغال والركاب يشوفون كيتك.');
    } on DriverRepositoryException catch (exception) {
      setState(() {
        tracking = false;
        statusMessage = exception.message;
      });
    } catch (_) {
      setState(() {
        tracking = false;
        statusMessage = 'ما قدرنا نشغل التتبع. جرّب مرة ثانية.';
      });
    }
  }

  Future<void> _sendPosition(Position position) async {
    try {
      await widget.repository.updateVehicleLocation(
        vehicleId: widget.vehicle.id,
        lat: position.latitude,
        lng: position.longitude,
        speedMetersPerSecond: position.speed.isFinite && position.speed >= 0
            ? position.speed
            : null,
      );
      if (!mounted) return;
      setState(() {
        lastPosition = position;
        tracking = true;
        statusMessage = 'التتبع شغال والركاب يشوفون كيتك.';
      });
    } on DriverRepositoryException catch (exception) {
      if (!mounted) return;
      setState(() => statusMessage = exception.message);
    }
  }

  Future<void> _loadPassengerWaits() async {
    try {
      final next = await widget.repository.activePassengerWaits(
        widget.route.id,
      );
      if (!mounted) return;
      setState(() => waits = next);
    } catch (_) {
      if (!mounted) return;
      setState(() => statusMessage = 'ما قدرنا نحدث ركاب الانتظار.');
    }
  }

  Future<void> _confirmStop() async {
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
      await _stopTracking();
    }
  }

  Future<void> _stopTracking() async {
    if (stopping) return;
    setState(() => stopping = true);
    await positionSubscription?.cancel();
    waitsTimer?.cancel();
    try {
      await widget.repository.stopVehicleTracking(widget.vehicle.id);
      if (!mounted) return;
      setState(() => tracking = false);
      Navigator.pop(context);
    } on DriverRepositoryException catch (exception) {
      if (!mounted) return;
      setState(() {
        stopping = false;
        statusMessage = exception.message;
      });
    }
  }
}

class _DriverNavigationSheet extends StatelessWidget {
  const _DriverNavigationSheet({
    required this.routeName,
    required this.plateNumber,
    required this.tracking,
    required this.stopping,
    required this.statusMessage,
    required this.waits,
    required this.nearestWait,
    required this.lastPosition,
    required this.onStop,
  });

  final String routeName;
  final String plateNumber;
  final bool tracking;
  final bool stopping;
  final String? statusMessage;
  final List<PassengerWaitPoint> waits;
  final PassengerWaitPoint? nearestWait;
  final Position? lastPosition;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final distance = nearestWait == null ? null : _distanceToWait(nearestWait!);
    final hasPassenger = nearestWait != null;
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
                  borderRadius: BorderRadius.circular(99),
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
                        : colors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasPassenger ? Icons.navigation : Icons.sensors,
                    color: hasPassenger
                        ? Colors.orange.shade900
                        : colors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPassenger ? 'روح لأقرب راكب' : 'استمر على خطك',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasPassenger
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
                    color: hasPassenger
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
                  icon: tracking ? Icons.sensors : Icons.sensors_off_outlined,
                  label: tracking ? 'التتبع شغال' : 'التتبع متوقف',
                  color: tracking ? colors.primary : colors.error,
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
    final position = lastPosition;
    if (position == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
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

class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel();

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
            Icons.verified_user_outlined,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'حساب السائق',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'ادخل برقمك حتى نربط الكية بحسابك ونحمي التتبع.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
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

class _DriverTrackingMap extends StatefulWidget {
  const _DriverTrackingMap({
    required this.stops,
    required this.waits,
    required this.lastPosition,
    required this.routeName,
  });

  final List<DriverStop> stops;
  final List<PassengerWaitPoint> waits;
  final Position? lastPosition;
  final String routeName;

  @override
  State<_DriverTrackingMap> createState() => _DriverTrackingMapState();
}

class _DriverTrackingMapState extends State<_DriverTrackingMap> {
  GoogleMapController? controller;
  String? focusedWaitId;
  String? routeRequestKey;
  List<LatLng> roadToWait = const [];
  bool roadRouteLoaded = false;
  List<LatLng> roadRoute = const [];

  @override
  void initState() {
    super.initState();
    _loadTransitRoadRoute();
  }

  @override
  void didUpdateWidget(covariant _DriverTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nearestWait = _nearestWait;
    final positionChanged =
        oldWidget.lastPosition?.latitude != widget.lastPosition?.latitude ||
        oldWidget.lastPosition?.longitude != widget.lastPosition?.longitude;
    final waitsChanged =
        oldWidget.waits.map((wait) => wait.id).join(',') !=
        widget.waits.map((wait) => wait.id).join(',');

    if (oldWidget.stops.map((s) => '${s.lat},${s.lng}').join(',') !=
        widget.stops.map((s) => '${s.lat},${s.lng}').join(',')) {
      _loadTransitRoadRoute();
    }

    if (nearestWait != null &&
        (focusedWaitId != nearestWait.id || positionChanged)) {
      _focusOnWait(nearestWait);
      _loadRoadToWait(nearestWait);
      return;
    }
    if (waitsChanged || positionChanged) {
      _focusBestTarget();
      if (nearestWait != null) _loadRoadToWait(nearestWait);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _initialCenter;
    if (center == null) {
      return _StatePanel(
        icon: Icons.map_outlined,
        title: 'الخريطة تنتظر الموقع',
        message: 'أول ما يوصل موقع الكية راح تظهر الخريطة هنا.',
      );
    }

    final colors = Theme.of(context).colorScheme;
    final nearestWait = _nearestWait;
    final distance = nearestWait == null ? null : _distanceToWait(nearestWait);
    final roadPoints = _guidancePoints(nearestWait);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: (nextController) {
              controller = nextController;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusBestTarget();
              });
            },
            initialCameraPosition: CameraPosition(target: center, zoom: 14.8),
            mapType: MapType.normal,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
            markers: _markers,
            polylines: {
              if (widget.stops.length > 1) ...[
                Polyline(
                  polylineId: const PolylineId('route_path_shadow'),
                  points: roadRoute.isNotEmpty
                      ? roadRoute
                      : widget.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList(),
                  color: Colors.white,
                  width: 8,
                  zIndex: 1,
                ),
                Polyline(
                  polylineId: const PolylineId('route_path'),
                  points: roadRoute.isNotEmpty
                      ? roadRoute
                      : widget.stops.map((stop) => LatLng(stop.lat, stop.lng)).toList(),
                  color: colors.primary.withValues(alpha: 0.82),
                  width: 5,
                  zIndex: 2,
                ),
              ],
              if (widget.lastPosition != null &&
                  nearestWait != null &&
                  roadPoints.length > 1)
                Polyline(
                  polylineId: const PolylineId('driver_to_nearest_wait'),
                  points: roadPoints,
                  color: Colors.orange.shade800,
                  width: 7,
                  zIndex: 6,
                  patterns: roadRouteLoaded
                      ? const []
                      : [PatternItem.dash(18), PatternItem.gap(10)],
                ),
            },
            circles: {
              if (nearestWait != null)
                Circle(
                  circleId: const CircleId('nearest_wait_area'),
                  center: LatLng(nearestWait.lat, nearestWait.lng),
                  radius: 85,
                  fillColor: Colors.orange.withValues(alpha: 0.16),
                  strokeColor: Colors.orange.shade800,
                  strokeWidth: 3,
                ),
              if (widget.lastPosition != null)
                Circle(
                  circleId: const CircleId('driver_area'),
                  center: LatLng(
                    widget.lastPosition!.latitude,
                    widget.lastPosition!.longitude,
                  ),
                  radius: 70,
                  fillColor: colors.primary.withValues(alpha: 0.14),
                  strokeColor: colors.primary.withValues(alpha: 0.36),
                  strokeWidth: 2,
                ),
            },
          ),
          if (nearestWait != null)
            PositionedDirectional(
              start: 10,
              end: 10,
              top: 10,
              child: Material(
                color: Colors.white,
                elevation: 4,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _focusOnWait(nearestWait),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.navigation,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'روح لهنا',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                distance == null
                                    ? 'أقرب راكب محدد على الخريطة'
                                    : roadRouteLoaded
                                    ? 'طريق الشوارع إلى أقرب راكب، يبعد ${_formatDistance(distance)}'
                                    : 'خط مباشر مؤقت، يبعد ${_formatDistance(distance)}',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.center_focus_strong),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  LatLng? get _initialCenter {
    final nearestWait = _nearestWait;
    if (nearestWait != null) {
      return LatLng(nearestWait.lat, nearestWait.lng);
    }
    if (widget.lastPosition != null) {
      return LatLng(
        widget.lastPosition!.latitude,
        widget.lastPosition!.longitude,
      );
    }
    if (widget.stops.isNotEmpty) {
      return LatLng(widget.stops.first.lat, widget.stops.first.lng);
    }
    if (widget.waits.isNotEmpty) {
      return LatLng(widget.waits.first.lat, widget.waits.first.lng);
    }
    return null;
  }

  Set<Marker> get _markers {
    final nearestWait = _nearestWait;
    return {
      for (final stop in widget.stops)
        Marker(
          markerId: MarkerId('stop_${stop.id}'),
          position: LatLng(stop.lat, stop.lng),
          icon: stop.isMajor
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(
            title: stop.nameAr,
            snippet: stop.landmarkAr.isEmpty
                ? widget.routeName
                : stop.landmarkAr,
          ),
          zIndexInt: stop.isMajor ? 4 : 3,
        ),
      for (final wait in widget.waits)
        Marker(
          markerId: MarkerId('wait_${wait.id}'),
          position: LatLng(wait.lat, wait.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            wait.id == nearestWait?.id
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueYellow,
          ),
          infoWindow: InfoWindow(
            title: wait.id == nearestWait?.id ? 'روح لهنا' : 'راكب ينتظر',
            snippet: 'ظاهر للسائقين',
          ),
          zIndexInt: wait.id == nearestWait?.id ? 14 : 8,
        ),
      if (widget.lastPosition != null)
        Marker(
          markerId: const MarkerId('driver_vehicle'),
          position: LatLng(
            widget.lastPosition!.latitude,
            widget.lastPosition!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'موقع كيتك الحالي'),
          zIndexInt: 12,
        ),
    };
  }

  PassengerWaitPoint? get _nearestWait {
    if (widget.waits.isEmpty) return null;
    final sorted = [...widget.waits];
    sorted.sort((a, b) {
      final distanceA = _distanceToWait(a) ?? 0;
      final distanceB = _distanceToWait(b) ?? 0;
      return distanceA.compareTo(distanceB);
    });
    return sorted.first;
  }

  double? _distanceToWait(PassengerWaitPoint wait) {
    final position = widget.lastPosition;
    if (position == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      wait.lat,
      wait.lng,
    );
  }

  void _focusBestTarget() {
    final nearestWait = _nearestWait;
    if (nearestWait != null) {
      _focusOnWait(nearestWait);
      _loadRoadToWait(nearestWait);
      return;
    }
    final position = widget.lastPosition;
    if (position != null) {
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    }
  }

  void _focusOnWait(PassengerWaitPoint wait) {
    focusedWaitId = wait.id;
    final position = widget.lastPosition;
    if (position == null) {
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(wait.lat, wait.lng), 16),
      );
      return;
    }
    final bounds = _boundsFor([
      LatLng(position.latitude, position.longitude),
      LatLng(wait.lat, wait.lng),
      ...roadToWait,
    ]);
    controller?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  List<LatLng> _guidancePoints(PassengerWaitPoint? wait) {
    final position = widget.lastPosition;
    if (position == null || wait == null) return const [];
    if (roadToWait.length > 1) return roadToWait;
    return [
      LatLng(position.latitude, position.longitude),
      LatLng(wait.lat, wait.lng),
    ];
  }

  Future<void> _loadRoadToWait(PassengerWaitPoint wait) async {
    final position = widget.lastPosition;
    if (position == null) return;
    final requestKey = [
      position.latitude.toStringAsFixed(5),
      position.longitude.toStringAsFixed(5),
      wait.lat.toStringAsFixed(5),
      wait.lng.toStringAsFixed(5),
    ].join(',');
    if (routeRequestKey == requestKey) return;
    routeRequestKey = requestKey;

    final fallback = [
      LatLng(position.latitude, position.longitude),
      LatLng(wait.lat, wait.lng),
    ];
    try {
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/${position.longitude},${position.latitude};${wait.lng},${wait.lat}',
        {'overview': 'full', 'geometries': 'geojson'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        _setRoadRoute(fallback, loaded: false);
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>? ?? const [];
      final geometry = routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
      final coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? const [];
      final points = coordinates
          .whereType<List<dynamic>>()
          .where((point) => point.length >= 2)
          .map(
            (point) => LatLng(
              (point[1] as num).toDouble(),
              (point[0] as num).toDouble(),
            ),
          )
          .toList();
      _setRoadRoute(
        points.length > 1 ? points : fallback,
        loaded: points.length > 1,
      );
    } catch (_) {
      _setRoadRoute(fallback, loaded: false);
    }
  }

  void _setRoadRoute(List<LatLng> points, {required bool loaded}) {
    if (!mounted) return;
    setState(() {
      roadToWait = points;
      roadRouteLoaded = loaded;
    });
    final controller = this.controller;
    if (controller != null && points.length > 1) {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFor(points), 72),
      );
    }
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final point in points.skip(1)) {
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
    }
    if (south == north) {
      south -= 0.001;
      north += 0.001;
    }
    if (west == east) {
      west -= 0.001;
      east += 0.001;
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Future<void> _loadTransitRoadRoute() async {
    if (widget.stops.length < 2) return;
    try {
      final coordsString = widget.stops
          .map((stop) => '${stop.lng},${stop.lat}')
          .join(';');
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/$coordsString',
        {'overview': 'full', 'geometries': 'geojson'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>? ?? const [];
        final geometry = routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List<dynamic>? ?? const [];
        final points = coordinates
            .whereType<List<dynamic>>()
            .where((point) => point.length >= 2)
            .map(
              (point) => LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ),
            )
            .toList();
        if (points.length > 1 && mounted) {
          setState(() {
            roadRoute = points;
          });
        }
      }
    } catch (_) {}
  }
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${_arabicDigits(meters.round())} م';
  return '${_arabicDigits((meters / 1000).toStringAsFixed(1))} كم';
}

String _arabicDigits(Object value) {
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var result = value.toString();
  for (var index = 0; index < western.length; index += 1) {
    result = result.replaceAll(western[index], arabic[index]);
  }
  return result;
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(message),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class SlideToToggle extends StatefulWidget {
  const SlideToToggle({
    super.key,
    required this.onTriggered,
    required this.label,
    this.enabled = true,
  });

  final VoidCallback onTriggered;
  final String label;
  final bool enabled;

  @override
  State<SlideToToggle> createState() => _SlideToToggleState();
}

class _SlideToToggleState extends State<SlideToToggle> {
  double _dragPosition = 0;
  static const double _width = 280;
  static const double _buttonSize = 50;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onHorizontalDragUpdate: widget.enabled
            ? (details) {
                setState(() {
                  _dragPosition -= details.delta.dx;
                  if (_dragPosition < 0) _dragPosition = 0;
                  final maxDrag = _width - _buttonSize - 8;
                  if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                });
              }
            : null,
        onHorizontalDragEnd: widget.enabled
            ? (details) {
                final maxDrag = _width - _buttonSize - 8;
                if (_dragPosition >= maxDrag * 0.8) {
                  widget.onTriggered();
                }
                setState(() {
                  _dragPosition = 0;
                });
              }
            : null,
        child: Container(
          width: _width,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PositionedDirectional(
                start: _dragPosition + 4,
                top: 2,
                bottom: 2,
                child: Container(
                  width: _buttonSize,
                  height: _buttonSize,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
