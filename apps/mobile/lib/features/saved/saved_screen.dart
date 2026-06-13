import 'package:flutter/material.dart';

import '../../shared/models/transit_models.dart';
import '../../shared/widgets/route_card.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('المحفوظة')), body: ListView(padding: const EdgeInsets.all(16), children: const [RouteCard(route: sampleRoute)]));
  }
}
