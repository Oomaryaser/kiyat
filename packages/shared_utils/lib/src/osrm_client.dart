import 'dart:convert';
import 'package:http/http.dart' as http;

class SharedLatLng {
  final double latitude;
  final double longitude;

  const SharedLatLng(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedLatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

Future<List<SharedLatLng>> fetchOSRMRoute(List<SharedLatLng> points) async {
  if (points.length < 2) return points;
  try {
    final coordsString = points
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$coordsString',
      {'overview': 'full', 'geometries': 'geojson'},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>? ?? const [];
      final geometry = routes.firstOrNull?['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List<dynamic>? ?? const [];
      return coordinates
          .whereType<List<dynamic>>()
          .where((point) => point.length >= 2)
          .map(
            (point) => SharedLatLng(
              (point[1] as num).toDouble(),
              (point[0] as num).toDouble(),
            ),
          )
          .toList();
    }
  } catch (_) {}
  return points;
}
