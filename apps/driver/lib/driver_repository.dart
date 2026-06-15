import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

final apiBaseUrl = const String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:3000',
);

const _plateNumberKey = 'driver_plate_number';
const _accessTokenKey = 'driver_access_token';
const _refreshTokenKey = 'driver_refresh_token';
const _phoneKey = 'driver_phone';

class DriverRepository {
  DriverRepository()
    : _dio = Dio(
        BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  final Dio _dio;

  Future<DriverSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessTokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);
    final phone = prefs.getString(_phoneKey);
    if (accessToken == null || refreshToken == null || phone == null) {
      return null;
    }
    _setAccessToken(accessToken);
    return DriverSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      phone: phone,
    );
  }

  Future<void> sendOtp(String phone) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/send-otp',
        data: {'phone': phone},
      );
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نرسل رمز الدخول.');
    }
  }

  Future<DriverSession> verifyDriverOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/driver/verify-otp',
        data: {'phone': phone, 'otp': otp},
      );
      final session = DriverSession.fromJson(
        response.data ?? const {},
        phone: phone,
      );
      await saveSession(session);
      return session;
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('رمز الدخول غير صحيح أو منتهي.');
    }
  }

  Future<void> saveSession(DriverSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, session.accessToken);
    await prefs.setString(_refreshTokenKey, session.refreshToken);
    await prefs.setString(_phoneKey, session.phone);
    _setAccessToken(session.accessToken);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_phoneKey);
    _dio.options.headers.remove('Authorization');
  }

  Future<List<DriverRoute>> listRoutes() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/routes');
      final data = response.data?['data'] as List<dynamic>? ?? const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(DriverRoute.fromJson)
          .where((route) => route.id.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نقرأ خطوط السيرفر.');
    }
  }

  Future<DriverVehicle> createVehicle({
    required String routeId,
    required String plateNumber,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/tracking/routes/$routeId/vehicles',
        data: {'plateNumber': plateNumber},
      );
      await savePlateNumber(plateNumber);
      return DriverVehicle.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نسجل الكية على الخط.');
    }
  }

  Future<DriverVehicle> updateVehicleLocation({
    required String vehicleId,
    required double lat,
    required double lng,
    double? speedMetersPerSecond,
  }) async {
    final data = <String, dynamic>{'lat': lat, 'lng': lng};
    if (speedMetersPerSecond != null) {
      data['speedMetersPerSecond'] = speedMetersPerSecond;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/tracking/vehicles/$vehicleId/location',
        data: data,
      );
      return DriverVehicle.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نرسل موقع الكية.');
    }
  }

  Future<void> stopVehicleTracking(String vehicleId) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/tracking/vehicles/$vehicleId/stop',
      );
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نوقف التتبع بالسيرفر.');
    }
  }

  Future<List<PassengerWaitPoint>> activePassengerWaits(String routeId) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/tracking/routes/$routeId/passenger-waits/active',
      );
      final data = response.data ?? const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(PassengerWaitPoint.fromJson)
          .where((wait) => wait.id.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نحدث ركاب الانتظار.');
    }
  }

  Future<String> loadPlateNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_plateNumberKey) ?? 'كية';
  }

  Future<void> savePlateNumber(String plateNumber) async {
    final cleanPlate = plateNumber.trim();
    if (cleanPlate.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plateNumberKey, cleanPlate);
  }

  Future<DriverRouteDetail> routeDetail(String routeId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/routes/$routeId');
      return DriverRouteDetail.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw DriverRepositoryException.fromDio(error);
    } catch (_) {
      throw const DriverRepositoryException('ما قدرنا نجيب تفاصيل الخط.');
    }
  }

  void _setAccessToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }
}

class DriverSession {
  const DriverSession({
    required this.accessToken,
    required this.refreshToken,
    required this.phone,
  });

  final String accessToken;
  final String refreshToken;
  final String phone;

  factory DriverSession.fromJson(
    Map<String, dynamic> json, {
    required String phone,
  }) {
    return DriverSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      phone: phone,
    );
  }
}

class DriverRoute {
  const DriverRoute({
    required this.id,
    required this.nameAr,
    required this.fareMin,
    required this.fareMax,
    required this.operatingHoursStart,
    required this.operatingHoursEnd,
  });

  final String id;
  final String nameAr;
  final int fareMin;
  final int fareMax;
  final String operatingHoursStart;
  final String operatingHoursEnd;

  factory DriverRoute.fromJson(Map<String, dynamic> json) {
    return DriverRoute(
      id: json['id'] as String? ?? '',
      nameAr: json['nameAr'] as String? ?? 'خط بدون اسم',
      fareMin: (json['fareMin'] as num?)?.toInt() ?? 0,
      fareMax: (json['fareMax'] as num?)?.toInt() ?? 0,
      operatingHoursStart: _formatApiTime(json['operatingHoursStart']),
      operatingHoursEnd: _formatApiTime(json['operatingHoursEnd']),
    );
  }

  String get fareLabel {
    if (fareMin <= 0 && fareMax <= 0) return 'الأجرة غير محددة';
    if (fareMin == fareMax || fareMax <= 0) return '${_digits(fareMin)} د.ع';
    return '${_digits(fareMin)} - ${_digits(fareMax)} د.ع';
  }

  String get hoursLabel {
    if (operatingHoursStart.isEmpty && operatingHoursEnd.isEmpty) {
      return 'الوقت غير محدد';
    }
    return '$operatingHoursStart - $operatingHoursEnd';
  }
}

class DriverRouteDetail {
  const DriverRouteDetail({required this.route, required this.stops});

  final DriverRoute route;
  final List<DriverStop> stops;

  factory DriverRouteDetail.fromJson(Map<String, dynamic> json) {
    final routeStops =
        (json['routeStops'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => ((a['stopSequence'] as num?)?.toInt() ?? 0).compareTo(
              (b['stopSequence'] as num?)?.toInt() ?? 0,
            ),
          );
    return DriverRouteDetail(
      route: DriverRoute.fromJson(json),
      stops: routeStops.map(DriverStop.fromRouteStopJson).toList(),
    );
  }
}

class DriverStop {
  const DriverStop({
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

  factory DriverStop.fromRouteStopJson(Map<String, dynamic> json) {
    final stop = json['stop'] as Map<String, dynamic>? ?? const {};
    final location = stop['location'] as Map<String, dynamic>? ?? const {};
    final coordinates = location['coordinates'] as List<dynamic>? ?? const [];
    return DriverStop(
      id: stop['id'] as String? ?? json['stopId'] as String? ?? '',
      nameAr: stop['nameAr'] as String? ?? '',
      landmarkAr: stop['landmarkAr'] as String? ?? '',
      lat: coordinates.length > 1 ? (coordinates[1] as num).toDouble() : 0,
      lng: coordinates.isNotEmpty ? (coordinates[0] as num).toDouble() : 0,
      isMajor: json['isMajor'] as bool? ?? false,
    );
  }
}

class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.routeId,
    required this.plateNumber,
    required this.isTrackingActive,
    this.lat,
    this.lng,
    this.speedMetersPerSecond,
    this.lastSeenAt,
  });

  final String id;
  final String routeId;
  final String plateNumber;
  final bool isTrackingActive;
  final double? lat;
  final double? lng;
  final double? speedMetersPerSecond;
  final DateTime? lastSeenAt;

  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    return DriverVehicle(
      id: json['id'] as String? ?? '',
      routeId: json['routeId'] as String? ?? '',
      plateNumber: json['plateNumber'] as String? ?? 'كية',
      isTrackingActive: json['isTrackingActive'] as bool? ?? false,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      speedMetersPerSecond: (json['speedMetersPerSecond'] as num?)?.toDouble(),
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
    );
  }
}

class PassengerWaitPoint {
  const PassengerWaitPoint({
    required this.id,
    required this.lat,
    required this.lng,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final double lat;
  final double lng;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PassengerWaitPoint.fromJson(Map<String, dynamic> json) {
    return PassengerWaitPoint(
      id: json['id'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class DriverRepositoryException implements Exception {
  const DriverRepositoryException(this.message);

  final String message;

  factory DriverRepositoryException.fromDio(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const DriverRepositoryException(
        'ماكو اتصال بالسيرفر. تأكد من API_URL وتشغيل الباكند.',
      );
    }
    final statusCode = error.response?.statusCode;
    if (statusCode == 404) {
      return const DriverRepositoryException('هذا الخط أو الكية غير موجودين.');
    }
    if (statusCode != null && statusCode >= 500) {
      return const DriverRepositoryException(
        'السيرفر تعبان حالياً. جرّب بعد لحظات.',
      );
    }
    return const DriverRepositoryException('صار خطأ بالاتصال. جرّب مرة ثانية.');
  }

  @override
  String toString() => message;
}

String _formatApiTime(Object? value) {
  final raw = value as String?;
  if (raw == null || raw.isEmpty) return '';
  final parts = raw.split(':');
  if (parts.length < 2) return _digits(raw);
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts[1];
  final suffix = hour >= 12 ? 'م' : 'ص';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '${_digits(displayHour.toString())}:${_digits(minute)} $suffix';
}

String _digits(Object value) {
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var result = value.toString();
  for (var index = 0; index < western.length; index += 1) {
    result = result.replaceAll(western[index], arabic[index]);
  }
  return result;
}
