import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final apiClientProvider = Provider<Dio>((ref) {
  const secureStorage = FlutterSecureStorage();
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
        final token = await secureStorage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refresh = await secureStorage.read(key: 'refresh_token');
          if (refresh != null) {
            try {
              final response = await dio.post<dynamic>(
                '/auth/refresh',
                data: {'refreshToken': refresh},
              );
              final newAccess = response.data['accessToken'] as String;
              final newRefresh = response.data['refreshToken'] as String;
              await secureStorage.write(key: 'access_token', value: newAccess);
              await secureStorage.write(key: 'refresh_token', value: newRefresh);
              
              error.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
              final retry = await dio.fetch<dynamic>(error.requestOptions);
              return handler.resolve(retry);
            } catch (_) {
              await secureStorage.delete(key: 'access_token');
              await secureStorage.delete(key: 'refresh_token');
            }
          }
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
