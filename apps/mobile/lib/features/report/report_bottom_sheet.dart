import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/data/transit_repository.dart';

class ReportBottomSheet extends ConsumerStatefulWidget {
  const ReportBottomSheet({super.key, required this.routeId});

  final String routeId;

  @override
  ConsumerState<ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends ConsumerState<ReportBottomSheet> {
  String type = 'route_change';
  final descriptionController = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final description = descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء كتابة تفاصيل البلاغ.')),
      );
      return;
    }

    setState(() => loading = true);

    final repository = ref.read(transitRepositoryProvider);
    final success = await repository.submitReport(
      routeId: widget.routeId,
      reportType: type,
      description: description,
    );

    if (!mounted) return;
    setState(() => loading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مشكور! بلاغك يساعد الكل 💚'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل إرسال البلاغ. تأكد من الاتصال بالشبكة.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'بلّغ عن تغيير بالخط',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
              labelText: 'نوع البلاغ',
            ),
            items: const [
              DropdownMenuItem(
                value: 'route_change',
                child: Text('تغيير بالمسار'),
              ),
              DropdownMenuItem(
                value: 'fare_change',
                child: Text('تغيير بالسعر'),
              ),
              DropdownMenuItem(
                value: 'closed',
                child: Text('الخط متوقف'),
              ),
              DropdownMenuItem(
                value: 'now_running',
                child: Text('الخط شغال الآن'),
              ),
              DropdownMenuItem(
                value: 'other',
                child: Text('شيء آخر'),
              ),
            ],
            onChanged: loading
                ? null
                : (value) => setState(() => type = value ?? type),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: descriptionController,
            maxLines: 3,
            maxLength: 200,
            enabled: !loading,
            decoration: const InputDecoration(
              hintText: 'اكتب تفاصيل التغيير هنا لمساعدة بقية الركاب...',
              alignLabelWithHint: true,
              labelText: 'التفاصيل',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.description_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : _submitReport,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(loading ? 'جاري الإرسال...' : 'إرسال البلاغ'),
            ),
          ),
        ],
      ),
    );
  }
}
