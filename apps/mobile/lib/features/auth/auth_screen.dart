import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/ui/kiyat_logo.dart';
import 'auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          const Center(child: KiyatLogo(size: 58)),
          const SizedBox(height: 28),
          Text('رقم الهاتف', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '07XX XXX XXXX',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            enabled:
                !authState.otpSent && authState.status != AuthStatus.loading,
          ),
          if (authState.otpSent) ...[
            const SizedBox(height: 16),
            Text('رمز التحقق', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '٦ أرقام',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              enabled: authState.status != AuthStatus.loading,
            ),
          ],
          if (authState.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              authState.errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: authState.status == AuthStatus.loading
                ? null
                : () async {
                    if (!authState.otpSent) {
                      final phone = _phoneController.text.trim();
                      if (phone.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('الرجاء إدخال رقم الهاتف')),
                        );
                        return;
                      }
                      await ref.read(authProvider.notifier).sendOtp(phone);
                    } else {
                      final otp = _otpController.text.trim();
                      final phone = _phoneController.text.trim();
                      if (otp.isEmpty || otp.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'الرجاء إدخال رمز التحقق المكون من 6 أرقام')),
                        );
                        return;
                      }
                      await ref
                          .read(authProvider.notifier)
                          .verifyOtp(phone, otp);
                    }
                  },
            child: authState.status == AuthStatus.loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(authState.otpSent ? 'دخول' : 'إرسال الرمز'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: authState.status == AuthStatus.loading
                ? null
                : () async {
                    var phone = _phoneController.text.trim();
                    if (phone.isEmpty || phone.length < 10) {
                      phone = '07701234567';
                      _phoneController.text = phone;
                    }
                    await ref.read(authProvider.notifier).devLogin(phone);
                  },
            icon: const Icon(Icons.login),
            label: const Text('دخول سريع (تجريبي 123456)'),
          ),
        ],
      ),
    );
  }
}
