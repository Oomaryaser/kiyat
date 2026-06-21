import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/home/home_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/route_detail/route_detail_screen.dart';
import '../../features/settings/settings_screen.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loggedIn = authState.status == AuthStatus.authenticated;
      final loggingIn = state.matchedLocation == '/auth';

      if (authState.status == AuthStatus.loading) return null;

      if (!loggedIn) {
        return loggingIn ? null : '/auth';
      }

      if (loggingIn) {
        return '/';
      }

      return null;
    },
    refreshListenable: GoRouterRefreshStream(ref.watch(authProvider.notifier).stream),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
      GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen()),
      GoRoute(
        path: '/routes/:id',
        builder: (context, state) =>
            RouteDetailScreen(routeId: state.pathParameters['id'] ?? 'sample'),
      ),
    ],
  );
});
