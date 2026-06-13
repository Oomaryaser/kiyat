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
  });

  final String vehicleLabel;
  final String nearStopName;
  final int etaMinutes;
  final int distanceMeters;
  final bool hasPassedPickup;
  final double lat;
  final double lng;
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
  TransitStop(id: 'bab', nameAr: 'الباب الشرقي', landmarkAr: 'قرب ساحة التحرير', lat: 33.3152, lng: 44.4161, isMajor: true),
  TransitStop(id: 'salhiya', nameAr: 'الصالحية', landmarkAr: 'قرب مبنى الإذاعة والتلفزيون', lat: 33.3236, lng: 44.3959, isMajor: false),
  TransitStop(id: 'atifiya', nameAr: 'العطيفية', landmarkAr: 'قرب الجسر', lat: 33.3601, lng: 44.3656, isMajor: false),
  TransitStop(id: 'kadhimiya', nameAr: 'الكاظمية', landmarkAr: 'قرب الروضة الكاظمية', lat: 33.3792, lng: 44.3384, isMajor: true),
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
