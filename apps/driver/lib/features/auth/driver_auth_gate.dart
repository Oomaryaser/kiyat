import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import '../routes/driver_home_screen.dart';
import 'driver_auth_screen.dart';

class DriverAuthGate extends ConsumerWidget {
  const DriverAuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(driverAuthProvider);

    switch (authState.status) {
      case DriverAuthStatus.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case DriverAuthStatus.unauthenticated:
        return const DriverAuthScreen();
      case DriverAuthStatus.authenticated:
        return DriverHomeScreen(
          session: authState.session!,
        );
    }
  }
}
