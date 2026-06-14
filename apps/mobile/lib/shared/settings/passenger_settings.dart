import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/passenger_notifications.dart';

final passengerSettingsProvider =
    FutureProvider<PassengerSettings>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return PassengerSettings(
    arrivalAlertsEnabled: prefs.getBool(_arrivalAlertsKey) ?? true,
    autoOpenActiveWait: prefs.getBool(_autoOpenActiveWaitKey) ?? false,
  );
});

final passengerSettingsControllerProvider =
    Provider<PassengerSettingsController>((ref) {
  return PassengerSettingsController(ref);
});

class PassengerSettings {
  const PassengerSettings({
    required this.arrivalAlertsEnabled,
    required this.autoOpenActiveWait,
  });

  final bool arrivalAlertsEnabled;
  final bool autoOpenActiveWait;
}

class PassengerSettingsController {
  const PassengerSettingsController(this._ref);

  final Ref _ref;

  Future<void> setArrivalAlertsEnabled(bool value) async {
    if (value) {
      await passengerNotifications.requestPermission();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_arrivalAlertsKey, value);
    _ref.invalidate(passengerSettingsProvider);
  }

  Future<void> setAutoOpenActiveWait(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoOpenActiveWaitKey, value);
    _ref.invalidate(passengerSettingsProvider);
  }
}

const _arrivalAlertsKey = 'arrival_alerts_enabled';
const _autoOpenActiveWaitKey = 'auto_open_active_wait';
