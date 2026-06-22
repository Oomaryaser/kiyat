import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../driver_repository.dart';

enum DriverAuthStatus { authenticated, unauthenticated, loading }

class DriverAuthState {
  final DriverAuthStatus status;
  final DriverSession? session;
  final String? errorMessage;
  final bool otpSent;

  const DriverAuthState({
    required this.status,
    this.session,
    this.errorMessage,
    this.otpSent = false,
  });

  DriverAuthState copyWith({
    DriverAuthStatus? status,
    DriverSession? session,
    String? errorMessage,
    bool? otpSent,
  }) {
    return DriverAuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      errorMessage: errorMessage ?? this.errorMessage,
      otpSent: otpSent ?? this.otpSent,
    );
  }
}

class DriverAuthNotifier extends Notifier<DriverAuthState> {
  late final DriverRepository _repository;

  @override
  DriverAuthState build() {
    _repository = ref.watch(driverRepositoryProvider);
    _checkAuth();
    return const DriverAuthState(status: DriverAuthStatus.loading);
  }

  Future<void> _checkAuth() async {
    try {
      final session = await _repository.loadSession();
      if (session != null) {
        state = DriverAuthState(status: DriverAuthStatus.authenticated, session: session);
      } else {
        state = const DriverAuthState(status: DriverAuthStatus.unauthenticated);
      }
    } catch (_) {
      state = const DriverAuthState(status: DriverAuthStatus.unauthenticated);
    }
  }

  Future<void> signIn(DriverSession session) async {
    await _repository.saveSession(session);
    state = DriverAuthState(status: DriverAuthStatus.authenticated, session: session);
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const DriverAuthState(status: DriverAuthStatus.unauthenticated);
  }
}

final driverAuthProvider = NotifierProvider<DriverAuthNotifier, DriverAuthState>(() {
  return DriverAuthNotifier();
});
