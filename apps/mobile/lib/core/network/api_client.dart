import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final apiClientProvider = Provider<Dio>((ref) {
  const secureStorage = FlutterSecureStorage();
  var refreshInFlight = false;
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://127.0.0.1:3000',
      ),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await secureStorage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final isRefreshRequest = error.requestOptions.path == '/auth/refresh';
        if (error.response?.statusCode == 401 &&
            !isRefreshRequest &&
            !refreshInFlight) {
          final refresh = await secureStorage.read(key: 'refresh_token');
          if (refresh != null) {
            try {
              refreshInFlight = true;
              final refreshDio = Dio(
                BaseOptions(
                  baseUrl: dio.options.baseUrl,
                  connectTimeout: const Duration(seconds: 10),
                  receiveTimeout: const Duration(seconds: 15),
                  sendTimeout: const Duration(seconds: 10),
                  responseType: ResponseType.json,
                ),
              );
              final response = await refreshDio.post<Map<String, dynamic>>(
                '/auth/refresh',
                data: {'refreshToken': refresh},
              );
              final data = response.data;
              final newAccess = data?['accessToken'] as String?;
              final newRefresh = data?['refreshToken'] as String?;
              if (newAccess == null || newRefresh == null) {
                throw StateError('Refresh response missing tokens');
              }
              await secureStorage.write(key: 'access_token', value: newAccess);
              await secureStorage.write(
                  key: 'refresh_token', value: newRefresh);

              error.requestOptions.headers['Authorization'] =
                  'Bearer $newAccess';
              final retry = await dio.fetch<dynamic>(error.requestOptions);
              return handler.resolve(retry);
            } catch (_) {
              await secureStorage.delete(key: 'access_token');
              await secureStorage.delete(key: 'refresh_token');
            } finally {
              refreshInFlight = false;
            }
          }
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
