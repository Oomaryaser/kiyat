enum RouteType { kia, coaster, bus, minibus }

enum RouteStatus { active, inactive, unverified }

class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.nameAr,
    required this.routeType,
    required this.status,
    required this.fareMin,
    required this.fareMax,
    required this.operatingHoursStart,
    required this.operatingHoursEnd,
    required this.confidenceScore,
    required this.lastVerifiedAt,
  });

  final String id;
  final String nameAr;
  final RouteType routeType;
  final RouteStatus status;
  final int fareMin;
  final int fareMax;
  final String operatingHoursStart;
  final String operatingHoursEnd;
  final int confidenceScore;
  final DateTime? lastVerifiedAt;

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      id: json['id'] as String,
      nameAr: json['nameAr'] as String? ?? '',
      routeType: RouteTypeX.fromApi(json['routeType'] as String?),
      status: RouteStatusX.fromApi(json['status'] as String?),
      fareMin: (json['fareMin'] as num?)?.toInt() ?? 0,
      fareMax: (json['fareMax'] as num?)?.toInt() ?? 0,
      operatingHoursStart:
          _formatApiTime(json['operatingHoursStart'] as String?),
      operatingHoursEnd: _formatApiTime(json['operatingHoursEnd'] as String?),
      confidenceScore: (json['confidenceScore'] as num?)?.toInt() ?? 50,
      lastVerifiedAt:
          DateTime.tryParse(json['lastVerifiedAt'] as String? ?? ''),
    );
  }
}

class TransitRouteDetail {
  const TransitRouteDetail({required this.route, required this.stops});

  final TransitRoute route;
  final List<TransitStop> stops;

  factory TransitRouteDetail.fromJson(Map<String, dynamic> json) {
    final routeStops = (json['routeStops'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => ((a['stopSequence'] as num?)?.toInt() ?? 0)
          .compareTo((b['stopSequence'] as num?)?.toInt() ?? 0));
    return TransitRouteDetail(
      route: TransitRoute.fromJson(json),
      stops: routeStops.map(TransitStop.fromRouteStopJson).toList(),
    );
  }
}

class TransitStop {
  const TransitStop({
    required this.id,
    required this.nameAr,
    required this.landmarkAr,
    required this.lat,
    required this.lng,
    required this.isMajor,
  });

  final String id;
  final String nameAr;
  final String landmarkAr;
  final double lat;
  final double lng;
  final bool isMajor;

  factory TransitStop.fromRouteStopJson(Map<String, dynamic> json) {
    final stop = json['stop'] as Map<String, dynamic>? ?? const {};
    final location = stop['location'] as Map<String, dynamic>? ?? const {};
    final coordinates = location['coordinates'] as List<dynamic>? ?? const [];
    return TransitStop(
      id: stop['id'] as String? ?? json['stopId'] as String? ?? '',
      nameAr: stop['nameAr'] as String? ?? '',
      landmarkAr: stop['landmarkAr'] as String? ?? '',
      lat: coordinates.length > 1 ? (coordinates[1] as num).toDouble() : 0,
      lng: coordinates.isNotEmpty ? (coordinates[0] as num).toDouble() : 0,
      isMajor: json['isMajor'] as bool? ?? false,
    );
  }
}

class VehicleArrivalEstimate {
  const VehicleArrivalEstimate({
    required this.vehicleLabel,
    required this.nearStopName,
    required this.etaMinutes,
    required this.distanceMeters,
    required this.hasPassedPickup,
    required this.lat,
    required this.lng,
    this.lastSeenAt,
  });

  final String vehicleLabel;
  final String nearStopName;
  final int etaMinutes;
  final int distanceMeters;
  final bool hasPassedPickup;
  final double lat;
  final double lng;
  final DateTime? lastSeenAt;

  factory VehicleArrivalEstimate.fromJson(Map<String, dynamic> json) {
    final nearestStop = json['nearestStop'] as Map<String, dynamic>?;
    return VehicleArrivalEstimate(
      vehicleLabel: json['plateNumber'] as String? ??
          json['vehicleId'] as String? ??
          'كية',
      nearStopName: nearestStop?['nameAr'] as String? ?? 'الخط',
      etaMinutes: (json['etaMinutes'] as num?)?.toInt() ?? 1,
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      hasPassedPickup: json['hasPassedPickup'] as bool? ?? false,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
    );
  }
}

extension RouteTypeX on RouteType {
  static RouteType fromApi(String? value) {
    return switch (value) {
      'coaster' => RouteType.coaster,
      'bus' => RouteType.bus,
      'minibus' => RouteType.minibus,
      _ => RouteType.kia,
    };
  }
}

extension RouteStatusX on RouteStatus {
  static RouteStatus fromApi(String? value) {
    return switch (value) {
      'inactive' => RouteStatus.inactive,
      'unverified' => RouteStatus.unverified,
      _ => RouteStatus.active,
    };
  }
}

String _formatApiTime(String? value) {
  if (value == null || value.isEmpty) return '';
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts[1];
  final suffix = hour >= 12 ? 'م' : 'ص';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '${_toArabicDigits(displayHour.toString())}:$minute $suffix';
}

String _toArabicDigits(String value) {
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var result = value;
  for (var i = 0; i < western.length; i += 1) {
    result = result.replaceAll(western[i], arabic[i]);
  }
  return result;
}

const sampleRoute = TransitRoute(
  id: 'sample',
  nameAr: 'الباب الشرقي - الكاظمية',
  routeType: RouteType.kia,
  status: RouteStatus.active,
  fareMin: 500,
  fareMax: 1000,
  operatingHoursStart: '٦:٠٠ ص',
  operatingHoursEnd: '١٠:٠٠ م',
  confidenceScore: 78,
  lastVerifiedAt: null,
);

const sampleStops = [
  TransitStop(
      id: 'bab',
      nameAr: 'الباب الشرقي',
      landmarkAr: 'قرب ساحة التحرير',
      lat: 33.3152,
      lng: 44.4161,
      isMajor: true),
  TransitStop(
      id: 'salhiya',
      nameAr: 'الصالحية',
      landmarkAr: 'قرب مبنى الإذاعة والتلفزيون',
      lat: 33.3236,
      lng: 44.3959,
      isMajor: false),
  TransitStop(
      id: 'atifiya',
      nameAr: 'العطيفية',
      landmarkAr: 'قرب الجسر',
      lat: 33.3601,
      lng: 44.3656,
      isMajor: false),
  TransitStop(
      id: 'kadhimiya',
      nameAr: 'الكاظمية',
      landmarkAr: 'قرب الروضة الكاظمية',
      lat: 33.3792,
      lng: 44.3384,
      isMajor: true),
];

const sampleVehicles = [
  VehicleArrivalEstimate(
    vehicleLabel: 'كية ١',
    nearStopName: 'الباب الشرقي',
    etaMinutes: 6,
    distanceMeters: 2150,
    hasPassedPickup: false,
    lat: 33.3152,
    lng: 44.4161,
  ),
  VehicleArrivalEstimate(
    vehicleLabel: 'كية ٢',
    nearStopName: 'العطيفية',
    etaMinutes: 1,
    distanceMeters: 320,
    hasPassedPickup: true,
    lat: 33.3601,
    lng: 44.3656,
  ),
];
