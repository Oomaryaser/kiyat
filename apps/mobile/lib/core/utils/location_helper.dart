import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class KiyatLocation {
  static const double defaultLat = 33.3152;
  static const double defaultLng = 44.4161;

  static bool isOutsideIraq(double lat, double lng) {
    return lat < 29.0 || lat > 38.0 || lng < 38.0 || lng > 49.0;
  }

  static Position mockBaghdad(DateTime timestamp) {
    // Offset the mock location slightly (approx 180m south-east) so there's walking distance to the first stop (33.3152, 44.4161)
    return Position(
      latitude: defaultLat - 0.0012,
      longitude: defaultLng + 0.0012,
      timestamp: timestamp,
      accuracy: 10.0,
      altitude: 34.0,
      altitudeAccuracy: 1.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  static Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
    if (kDebugMode && isOutsideIraq(pos.latitude, pos.longitude)) {
      return mockBaghdad(pos.timestamp);
    }
    return pos;
  }

  static Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    return Geolocator.getPositionStream(locationSettings: locationSettings).map((pos) {
      if (kDebugMode && isOutsideIraq(pos.latitude, pos.longitude)) {
        return mockBaghdad(pos.timestamp);
      }
      return pos;
    });
  }
}
