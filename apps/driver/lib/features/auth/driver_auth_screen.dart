import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../driver_repository.dart';
import '../../shared/widgets/state_panel.dart';
import 'auth_provider.dart';

class DriverAuthScreen extends ConsumerStatefulWidget {
  const DriverAuthScreen({super.key});

  @override
  ConsumerState<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends ConsumerState<DriverAuthScreen> {
  final PageController _pageController = PageController();
  final phoneController = TextEditingController(text: '+964');
  
  // OTP variables
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  int _step = 0; // 0: Phone, 1: OTP
  bool loading = false;
  String? error;
  
  // Resend OTP Timer
  Timer? _resendTimer;
  int _resendSeconds = 60;
  bool _canResend = false;

  DriverRepository get _repository => ref.read(driverRepositoryProvider);

  @override
  void dispose() {
    _pageController.dispose();
    phoneController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = 60;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        setState(() {
          _canResend = true;
          _resendTimer?.cancel();
        });
      }
    });
  }

  String _cleanPhoneNumber(String raw) {
    var phone = raw.trim();
    if (phone.startsWith('07')) {
      phone = '+964${phone.substring(1)}';
    } else if (phone.startsWith('7')) {
      phone = '+964$phone';
    }
    return phone;
  }

  bool _validatePhone(String phone) {
    final clean = _cleanPhoneNumber(phone);
    return clean.startsWith('+9647') && clean.length == 13;
  }

  Future<void> _sendOtp() async {
    final phone = phoneController.text.trim();
    if (!_validatePhone(phone)) {
      setState(() => error = 'الرجاء إدخال رقم هاتف عراقي صحيح (مثال: 07701234567).');
      HapticFeedback.vibrate();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cleanPhone = _cleanPhoneNumber(phone);
      await _repository.sendOtp(cleanPhone);
      HapticFeedback.mediumImpact();
      _startResendTimer();
      setState(() {
        _step = 1;
        loading = false;
      });
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _otpFocusNodes[0].requestFocus();
        }
      });
    } on DriverRepositoryException catch (exception) {
      setState(() {
        error = exception.message;
        loading = false;
      });
      HapticFeedback.vibrate();
    } catch (_) {
      setState(() {
        error = 'تعذر إرسال الرمز. يرجى المحاولة لاحقاً.';
        loading = false;
      });
      HapticFeedback.vibrate();
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _cleanPhoneNumber(phoneController.text);
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      setState(() => error = 'الرجاء إدخال رمز التحقق المكون من 6 أرقام.');
      HapticFeedback.vibrate();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await _repository.verifyDriverOtp(
        phone: phone,
        otp: otp,
      );
      HapticFeedback.mediumImpact();
      ref.read(driverAuthProvider.notifier).signIn(session);
    } on DriverRepositoryException catch (exception) {
      setState(() {
        error = exception.message;
        loading = false;
      });
      HapticFeedback.vibrate();
    } catch (_) {
      setState(() {
        error = 'رمز التحقق غير صحيح أو منتهي الصلاحية.';
        loading = false;
      });
      HapticFeedback.vibrate();
    }
  }

  Future<void> _devLogin() async {
    var phone = phoneController.text.trim();
    if (!_validatePhone(phone)) {
      phone = '07701234567';
      phoneController.text = phone;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cleanPhone = _cleanPhoneNumber(phone);
      final session = await _repository.devDriverLogin(phone: cleanPhone);
      HapticFeedback.mediumImpact();
      ref.read(driverAuthProvider.notifier).signIn(session);
    } on DriverRepositoryException catch (exception) {
      setState(() {
        error = exception.message;
        loading = false;
      });
      HapticFeedback.vibrate();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _step == 0 ? 'تسجيل دخول السائق' : 'رمز التحقق',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _step = 0;
                    error = null;
                  });
                  _pageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              )
            : null,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildPhoneStep(),
          _buildOtpStep(),
        ],
      ),
    );
  }

  Widget _buildPhoneStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _LoginHeroPanel(),
        const SizedBox(height: 24),
        Text(
          'أدخل رقم الهاتف للبدء',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            hintText: '0770 123 4567',
            prefixIcon: Icon(Icons.phone_iphone_outlined),
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _sendOtp(),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          StatePanel(
            icon: Icons.error_outline,
            title: 'خطأ',
            message: error!,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: loading ? null : _sendOtp,
          icon: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.arrow_forward),
          label: const Text('إرسال رمز التأكيد (OTP)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: loading ? null : _devLogin,
          icon: const Icon(Icons.login),
          label: const Text('دخول سريع (تجريبي 123456)'),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'أدخل الرمز المكون من 6 أرقام المرسل إلى الرقم:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          phoneController.text.trim(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    if (index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    } else {
                      _otpFocusNodes[index].unfocus();
                      _verifyOtp(); // Auto submit
                    }
                  } else {
                    if (index > 0) {
                      _otpFocusNodes[index - 1].requestFocus();
                    }
                  }
                },
              ),
            );
          }),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          StatePanel(
            icon: Icons.error_outline,
            title: 'تعذر التحقق',
            message: error!,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: loading ? null : _verifyOtp,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('تأكيد الرمز والدخول'),
        ),
        const SizedBox(height: 16),
        Center(
          child: _canResend
              ? TextButton(
                  onPressed: _sendOtp,
                  child: const Text('إعادة إرسال الرمز'),
                )
              : Text(
                  'يمكنك إعادة الإرسال خلال $_resendSeconds ثانية',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
        ),
      ],
    );
  }
}

class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'حساب السائق',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'ادخل برقمك حتى نربط الكية بحسابك ونحمي التتبع.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
