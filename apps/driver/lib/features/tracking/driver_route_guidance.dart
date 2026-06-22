import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../driver_repository.dart';

class DriverRouteGuidance {
  const DriverRouteGuidance({
    required this.nearestPoint,
    required this.distanceMeters,
    required this.isOffRoute,
  });

  final LatLng nearestPoint;
  final double distanceMeters;
  final bool isOffRoute;

  factory DriverRouteGuidance.fromStops({
    required List<DriverStop> stops,
    required LatLng position,
    required double thresholdMeters,
  }) {
    final nearest = _nearestPointOnDriverRoute(position, stops);
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      nearest.latitude,
      nearest.longitude,
    );
    return DriverRouteGuidance(
      nearestPoint: nearest,
      distanceMeters: distance,
      isOffRoute: distance > thresholdMeters,
    );
  }
}

LatLng _nearestPointOnDriverRoute(LatLng point, List<DriverStop> stops) {
  if (stops.isEmpty) return point;
  if (stops.length == 1) return LatLng(stops.first.lat, stops.first.lng);

  var nearestPoint = LatLng(stops.first.lat, stops.first.lng);
  var minDistance = double.infinity;
  for (var index = 0; index < stops.length - 1; index += 1) {
    final projected = _projectPointToDriverSegment(
      point,
      LatLng(stops[index].lat, stops[index].lng),
      LatLng(stops[index + 1].lat, stops[index + 1].lng),
    );
    final distance = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      projected.latitude,
      projected.longitude,
    );
    if (distance < minDistance) {
      minDistance = distance;
      nearestPoint = projected;
    }
  }
  return nearestPoint;
}

LatLng _projectPointToDriverSegment(LatLng point, LatLng start, LatLng end) {
  final x = point.longitude;
  final y = point.latitude;
  final x1 = start.longitude;
  final y1 = start.latitude;
  final x2 = end.longitude;
  final y2 = end.latitude;
  final dx = x2 - x1;
  final dy = y2 - y1;
  final lenSq = dx * dx + dy * dy;
  var t = lenSq == 0 ? 0.0 : ((x - x1) * dx + (y - y1) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  return LatLng(y1 + dy * t, x1 + dx * t);
}
