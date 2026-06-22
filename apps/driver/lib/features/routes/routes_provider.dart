import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../driver_repository.dart';

final driverRoutesProvider = FutureProvider<List<DriverRoute>>((ref) async {
  return ref.watch(driverRepositoryProvider).listRoutes();
});

class SelectedRouteNotifier extends Notifier<DriverRoute?> {
  @override
  DriverRoute? build() => null;

  void select(DriverRoute? route) => state = route;
}

final selectedRouteProvider = NotifierProvider<SelectedRouteNotifier, DriverRoute?>(() {
  return SelectedRouteNotifier();
});

class PassengerCountNotifier extends Notifier<int> {
  static const _key = 'driver_passenger_count';

  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_key) ?? 0;
  }

  Future<void> increment() async {
    state++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, state);
  }

  Future<void> decrement() async {
    if (state > 0) {
      state--;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, state);
    }
  }

  Future<void> reset() async {
    state = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, state);
  }
}

final passengerCountProvider = NotifierProvider<PassengerCountNotifier, int>(() {
  return PassengerCountNotifier();
});
