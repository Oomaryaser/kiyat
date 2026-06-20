import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'driver_repository.dart';

void main() {
  runApp(const KiyatDriverApp());
}

class KiyatDriverApp extends StatelessWidget {
  const KiyatDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Tajawal',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF14532D),
          primary: const Color(0xFF14532D),
          secondary: const Color(0xFFF59E0B),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7F8),
          elevation: 0,
          centerTitle: false,
        ),
      ),
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
  final phoneController = TextEditingController(text: '+964');
  bool loading = false;
  String? error;

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'دخول السائق',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _LoginHeroPanel(),
          const SizedBox(height: 14),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              prefixIcon: Icon(Icons.phone_iphone_outlined),
              filled: true,
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _devLogin(),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _StatePanel(
              icon: Icons.error_outline,
              title: 'تعذر الدخول',
              message: error!,
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: loading ? null : _devLogin,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(loading ? 'انتظر...' : 'دخول تجريبي'),
          ),
        ),
      ),
    );
  }

  Future<void> _devLogin() async {
    final phone = phoneController.text.trim();
    if (phone.length < 8) {
      setState(() => error = 'اكتب رقم هاتف صحيح.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await widget.repository.devDriverLogin(phone: phone);
      if (!mounted) return;
      widget.onSignedIn(session);
    } on DriverRepositoryException catch (exception) {
      setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

class DriverHomeScreen extends StatefulWidget {
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
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final plateController = TextEditingController(text: 'كية');
  late Future<List<DriverRoute>> routesFuture;
  DriverRoute? selectedRoute;
  bool starting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    routesFuture = widget.repository.listRoutes();
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
        title: const Text(
          'كيات السائق',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل خروج',
          ),
        ],
      ),
      body: FutureBuilder<List<DriverRoute>>(
        future: routesFuture,
        builder: (context, snapshot) {
          final routes = snapshot.data ?? const <DriverRoute>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroPanel(onRefresh: _refreshRoutes),
              const SizedBox(height: 14),
              TextField(
                controller: plateController,
                decoration: const InputDecoration(
                  labelText: 'اسم/رقم الكية',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                  filled: true,
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
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
                    'اختار خطك',
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
          );
        },
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
            label: Text(starting ? 'دا نبدي...' : 'بدء التتبع'),
          ),
        ),
      ),
    );
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
    return PopScope(
      canPop: !tracking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تتبع الكية'),
          automaticallyImplyLeading: !tracking,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TrackingHeader(
              routeName: widget.route.nameAr,
              plateNumber: widget.vehicle.plateNumber,
              tracking: tracking,
              lastPosition: lastPosition,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
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
            const SizedBox(height: 12),
            _WaitingPassengersPanel(waits: waits, lastPosition: lastPosition),
            if (statusMessage != null) ...[
              const SizedBox(height: 12),
              _StatePanel(
                icon: Icons.info_outline,
                title: 'حالة التتبع',
                message: statusMessage!,
              ),
            ],
            const SizedBox(height: 90),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: stopping ? null : _confirmStop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(stopping ? 'دا نوقف...' : 'إيقاف التتبع'),
            ),
          ),
        ),
      ),
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

  @override
  void didUpdateWidget(covariant _DriverTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final position = widget.lastPosition;
    final oldPosition = oldWidget.lastPosition;
    if (position == null) return;
    if (oldPosition == null ||
        oldPosition.latitude != position.latitude ||
        oldPosition.longitude != position.longitude) {
      controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GoogleMap(
        onMapCreated: (nextController) => controller = nextController,
        initialCameraPosition: CameraPosition(target: center, zoom: 13.8),
        mapType: MapType.normal,
        myLocationButtonEnabled: false,
        myLocationEnabled: false,
        compassEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        markers: _markers,
        polylines: {
          if (widget.stops.length > 1)
            Polyline(
              polylineId: const PolylineId('route_path_shadow'),
              points: widget.stops
                  .map((stop) => LatLng(stop.lat, stop.lng))
                  .toList(),
              color: Colors.white,
              width: 8,
              zIndex: 1,
            ),
          if (widget.stops.length > 1)
            Polyline(
              polylineId: const PolylineId('route_path'),
              points: widget.stops
                  .map((stop) => LatLng(stop.lat, stop.lng))
                  .toList(),
              color: colors.primary,
              width: 5,
              zIndex: 2,
            ),
        },
        circles: {
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
    );
  }

  LatLng? get _initialCenter {
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
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'راكب ينتظر'),
          zIndexInt: 8,
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
}

class _TrackingHeader extends StatelessWidget {
  const _TrackingHeader({
    required this.routeName,
    required this.plateNumber,
    required this.tracking,
    required this.lastPosition,
  });

  final String routeName;
  final String plateNumber;
  final bool tracking;
  final Position? lastPosition;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tracking ? colors.primary : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tracking ? Icons.sensors : Icons.sensors_off_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                tracking ? 'التتبع شغال' : 'التتبع متوقف',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            routeName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            plateNumber,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
          ),
          if (lastPosition != null) ...[
            const SizedBox(height: 12),
            Text(
              'آخر تحديث: ${lastPosition!.latitude.toStringAsFixed(5)}, ${lastPosition!.longitude.toStringAsFixed(5)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
            ),
          ],
        ],
      ),
    );
  }
}

class _WaitingPassengersPanel extends StatelessWidget {
  const _WaitingPassengersPanel({
    required this.waits,
    required this.lastPosition,
  });

  final List<PassengerWaitPoint> waits;
  final Position? lastPosition;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_outlined),
              const SizedBox(width: 8),
              Text(
                'ركاب ظاهرين إلك',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                '${waits.length}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (waits.isEmpty)
            Text(
              'ماكو ركاب ظاهرين على خطك حالياً. أول ما الراكب يضغط انتظار راح يطلع هنا.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            ...waits.take(5).map((wait) {
              final distance = _distanceToWait(wait);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_pin_circle_outlined),
                title: Text(
                  distance == null
                      ? 'راكب ينتظر على الخط'
                      : 'راكب يبعد ${_formatDistance(distance)}',
                ),
                subtitle: Text(
                  'ظاهر للسائقين'
                  '${wait.updatedAt == null ? '' : ' • ${_relativeTime(wait.updatedAt!)}'}',
                ),
              );
            }),
        ],
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

String _relativeTime(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime.toLocal());
  if (difference.inMinutes < 1) return 'الآن';
  if (difference.inMinutes < 60) {
    return 'قبل ${_arabicDigits(difference.inMinutes)} د';
  }
  return 'قبل ${_arabicDigits(difference.inHours)} س';
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
