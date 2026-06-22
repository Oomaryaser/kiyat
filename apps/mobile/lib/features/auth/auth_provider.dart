import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';

enum AuthStatus { authenticated, unauthenticated, loading }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final bool otpSent;

  AuthState({
    required this.status,
    this.errorMessage,
    this.otpSent = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    bool? otpSent,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      otpSent: otpSent ?? this.otpSent,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;
  static const _secureStorage = FlutterSecureStorage();

  AuthNotifier(this._dio) : super(AuthState(status: AuthStatus.loading)) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final token = await _secureStorage.read(key: 'access_token');
      if (token != null) {
        state = AuthState(status: AuthStatus.authenticated);
      } else {
        state = AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (_) {
      state = AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> sendOtp(String phone) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      await _dio.post<Map<String, dynamic>>('/auth/send-otp', data: {'phone': phone});
      state = state.copyWith(status: AuthStatus.unauthenticated, otpSent: true);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? 'خطأ في إرسال الرمز';
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: msg is List ? msg.join(', ') : msg.toString(),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'تعذر الاتصال بالسيرفر',
      );
      return false;
    }
  }

  Future<bool> verifyOtp(String phone, String otp) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _dio.post<Map<String, dynamic>>('/auth/verify-otp', data: {
        'phone': phone,
        'otp': otp,
      });
      final data = response.data;
      if (data == null) throw Exception('No data returned');
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String;

      await _secureStorage.write(key: 'access_token', value: accessToken);
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('passenger_phone', phone);

      state = AuthState(status: AuthStatus.authenticated);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? 'رمز التحقق غير صحيح';
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        otpSent: true,
        errorMessage: msg is List ? msg.join(', ') : msg.toString(),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        otpSent: true,
        errorMessage: 'خطأ في التحقق من الرمز',
      );
      return false;
    }
  }

  Future<bool> devLogin(String phone) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final otpSentSuccess = await sendOtp(phone);
      if (!otpSentSuccess) return false;
      return await verifyOtp(phone, '123456');
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'خطأ في الدخول التجريبي',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'access_token');
    await _secureStorage.delete(key: 'refresh_token');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('passenger_phone');

    state = AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(apiClientProvider));
});
