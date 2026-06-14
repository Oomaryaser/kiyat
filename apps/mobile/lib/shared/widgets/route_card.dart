import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/transit_models.dart';

class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    this.isActiveWait = false,
    this.disabled = false,
    this.distanceMeters,
  });

  final TransitRoute route;
  final bool isActiveWait;
  final bool disabled;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: isActiveWait ? colors.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: disabled ? null : () => context.push('/routes/${route.id}'),
        child: Opacity(
          opacity: disabled ? 0.42 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isActiveWait) ...[
                  Row(
                    children: [
                      Icon(Icons.radio_button_checked,
                          size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Text('تنتظر هذا الخط حالياً',
                          style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.primary.withValues(alpha: 0.1),
                      child: Text(_typeLabel(route.routeType),
                          style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(route.nameAr,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    if (disabled)
                      const Icon(Icons.lock_outline, size: 20)
                    else if (distanceMeters != null)
                      _DistanceBadge(distanceMeters: distanceMeters!)
                    else
                      _ConfidenceBadge(score: route.confidenceScore),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text('${route.fareMin} - ${route.fareMax} د.ع'),
                    const SizedBox(width: 18),
                    const Icon(Icons.schedule, size: 18),
                    const SizedBox(width: 6),
                    Text(
                        '${route.operatingHoursStart} - ${route.operatingHoursEnd}'),
                  ],
                ),
                if (disabled) ...[
                  const SizedBox(height: 10),
                  const Text('موقف مؤقتاً لأن عندك خط تنتظره حالياً.',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(RouteType type) {
    return switch (type) {
      RouteType.kia => 'كية',
      RouteType.coaster => 'كوستر',
      RouteType.bus => 'باص',
      RouteType.minibus => 'ميني',
    };
  }
}

class _DistanceBadge extends StatelessWidget {
  const _DistanceBadge({required this.distanceMeters});

  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} كم'
        : '${distanceMeters.round()} م';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75 ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text('$score%',
          style: TextStyle(color: color.shade800, fontWeight: FontWeight.w700)),
    );
  }
}
