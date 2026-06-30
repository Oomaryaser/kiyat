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
    final points = stops.map((s) => LatLng(s.lat, s.lng)).toList();
    return DriverRouteGuidance.fromPoints(
      points: points,
      position: position,
      thresholdMeters: thresholdMeters,
    );
  }

  factory DriverRouteGuidance.fromPoints({
    required List<LatLng> points,
    required LatLng position,
    required double thresholdMeters,
  }) {
    final nearest = _nearestPointOnPoints(position, points);
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

LatLng _nearestPointOnPoints(LatLng point, List<LatLng> points) {
  if (points.isEmpty) return point;
  if (points.length == 1) return points.first;

  var nearestPoint = points.first;
  var minDistance = double.infinity;
  for (var index = 0; index < points.length - 1; index += 1) {
    final projected = _projectPointToDriverSegment(
      point,
      points[index],
      points[index + 1],
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
