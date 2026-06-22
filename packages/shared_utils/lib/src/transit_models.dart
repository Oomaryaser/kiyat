import 'arabic_utils.dart';

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
      id: json['id'] as String? ?? '',
      nameAr: json['nameAr'] as String? ?? '',
      routeType: RouteTypeX.fromApi(json['routeType'] as String?),
      status: RouteStatusX.fromApi(json['status'] as String?),
      fareMin: (json['fareMin'] as num?)?.toInt() ?? 0,
      fareMax: (json['fareMax'] as num?)?.toInt() ?? 0,
      operatingHoursStart:
          formatApiTime(json['operatingHoursStart'] as String?),
      operatingHoursEnd: formatApiTime(json['operatingHoursEnd'] as String?),
      confidenceScore: (json['confidenceScore'] as num?)?.toInt() ?? 50,
      lastVerifiedAt:
          DateTime.tryParse(json['lastVerifiedAt'] as String? ?? ''),
    );
  }

  String get fareLabel {
    if (fareMin <= 0 && fareMax <= 0) return 'الأجرة غير محددة';
    if (fareMin == fareMax || fareMax <= 0) return '${toArabicDigits(fareMin)} د.ع';
    return '${toArabicDigits(fareMin)} - ${toArabicDigits(fareMax)} د.ع';
  }

  String get hoursLabel {
    if (operatingHoursStart.isEmpty && operatingHoursEnd.isEmpty) {
      return 'الوقت غير محدد';
    }
    return '$operatingHoursStart - $operatingHoursEnd';
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
    this.etaConfidence = 'high',
    this.etaConfidenceLabel = 'التتبع نشط',
    this.lastSeenSeconds,
    this.notificationHint,
    this.lastSeenAt,
  });

  final String vehicleLabel;
  final String nearStopName;
  final int etaMinutes;
  final int distanceMeters;
  final bool hasPassedPickup;
  final double lat;
  final double lng;
  final String etaConfidence;
  final String etaConfidenceLabel;
  final int? lastSeenSeconds;
  final String? notificationHint;
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
      etaConfidence: json['etaConfidence'] as String? ?? 'high',
      etaConfidenceLabel:
          json['etaConfidenceLabel'] as String? ?? 'التتبع نشط',
      lastSeenSeconds: (json['lastSeenSeconds'] as num?)?.toInt(),
      notificationHint: json['notificationHint'] as String?,
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
