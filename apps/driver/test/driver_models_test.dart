import 'package:flutter_test/flutter_test.dart';
import 'package:kiyat_driver/driver_repository.dart';

void main() {
  test('driver route parses backend json', () {
    final route = DriverRoute.fromJson({
      'id': 'route-1',
      'nameAr': 'الباب الشرقي - الكاظمية',
    });

    expect(route.id, 'route-1');
    expect(route.nameAr, 'الباب الشرقي - الكاظمية');
  });

  test('passenger wait point parses coordinates', () {
    final wait = PassengerWaitPoint.fromJson({
      'id': 'wait-1',
      'lat': 33.3,
      'lng': 44.4,
      'updatedAt': '2026-06-15T10:00:00.000Z',
    });

    expect(wait.id, 'wait-1');
    expect(wait.lat, 33.3);
    expect(wait.lng, 44.4);
    expect(wait.updatedAt, isNotNull);
  });

  test('driver session parses auth response', () {
    final session = DriverSession.fromJson({
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
    }, phone: '+9647700000000');

    expect(session.accessToken, 'access-token');
    expect(session.refreshToken, 'refresh-token');
    expect(session.phone, '+9647700000000');
  });

  test('driver route detail sorts stops by sequence', () {
    final detail = DriverRouteDetail.fromJson({
      'id': 'route-1',
      'nameAr': 'خط تجريبي',
      'routeStops': [
        {
          'stopSequence': 2,
          'isMajor': false,
          'stop': {
            'id': 'b',
            'nameAr': 'الثانية',
            'landmarkAr': 'علامة ثانية',
            'location': {
              'coordinates': [44.2, 33.2],
            },
          },
        },
        {
          'stopSequence': 1,
          'isMajor': true,
          'stop': {
            'id': 'a',
            'nameAr': 'الأولى',
            'landmarkAr': 'علامة أولى',
            'location': {
              'coordinates': [44.1, 33.1],
            },
          },
        },
      ],
    });

    expect(detail.route.nameAr, 'خط تجريبي');
    expect(detail.stops.map((stop) => stop.id), ['a', 'b']);
    expect(detail.stops.first.isMajor, isTrue);
  });
}
