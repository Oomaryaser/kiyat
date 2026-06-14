import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiyat_mobile/shared/data/transit_repository.dart';
import 'package:kiyat_mobile/shared/settings/passenger_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saved route ids can be added and removed', () async {
    final repository = TransitRepository(Dio());

    await repository.setRouteSaved('route-a', true);
    await repository.setRouteSaved('route-b', true);

    expect(await repository.loadSavedRouteIds(), {'route-a', 'route-b'});
    expect(await repository.isRouteSaved('route-a'), isTrue);

    await repository.setRouteSaved('route-a', false);

    expect(await repository.loadSavedRouteIds(), {'route-b'});
    expect(await repository.isRouteSaved('route-a'), isFalse);
  });

  test('passenger settings persist alert and auto-open choices', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(passengerSettingsControllerProvider);

    await controller.setArrivalAlertsEnabled(false);
    await controller.setAutoOpenActiveWait(true);
    container.invalidate(passengerSettingsProvider);

    final settings = await container.read(passengerSettingsProvider.future);
    expect(settings.arrivalAlertsEnabled, isFalse);
    expect(settings.autoOpenActiveWait, isTrue);
  });
}
