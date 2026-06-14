import 'package:flutter/material.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool sent = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('رقم الهاتف', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const TextField(
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  hintText: '07XX XXX XXXX',
                  prefixIcon: Icon(Icons.phone_outlined))),
          if (sent) ...[
            const SizedBox(height: 16),
            Text('رمز التحقق', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const TextField(
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                    hintText: '٦ أرقام', prefixIcon: Icon(Icons.lock_outline))),
          ],
          const SizedBox(height: 18),
          FilledButton(
              onPressed: () => setState(() => sent = true),
              child: Text(sent ? 'دخول' : 'إرسال الرمز')),
        ],
      ),
    );
  }
}
