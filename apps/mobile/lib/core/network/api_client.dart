import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:3000',
      ),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final prefs = await SharedPreferences.getInstance();
          final refresh = prefs.getString('refresh_token');
          if (refresh != null) {
            final response = await dio.post<dynamic>('/auth/refresh',
                data: {'refreshToken': refresh});
            await prefs.setString(
                'access_token', response.data['accessToken'] as String);
            await prefs.setString(
                'refresh_token', response.data['refreshToken'] as String);
            final retry = await dio.fetch<dynamic>(error.requestOptions);
            return handler.resolve(retry);
          }
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
