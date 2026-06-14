import 'package:flutter/material.dart';

class ReportBottomSheet extends StatefulWidget {
  const ReportBottomSheet({super.key, required this.routeId});

  final String routeId;

  @override
  State<ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<ReportBottomSheet> {
  String type = 'route_change';

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بلّغ عن تغيير',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            items: const [
              DropdownMenuItem(
                  value: 'route_change', child: Text('تغيير بالمسار')),
              DropdownMenuItem(
                  value: 'fare_change', child: Text('تغيير بالسعر')),
              DropdownMenuItem(value: 'closed', child: Text('الخط متوقف')),
              DropdownMenuItem(
                  value: 'now_running', child: Text('الخط شغال الآن')),
              DropdownMenuItem(value: 'other', child: Text('شيء آخر')),
            ],
            onChanged: (value) => setState(() => type = value ?? type),
          ),
          const SizedBox(height: 12),
          const TextField(
              maxLines: 4,
              decoration: InputDecoration(hintText: 'اكتب التفاصيل')),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إرسال'))),
        ],
      ),
    );
  }
}
