import 'package:flutter/material.dart';
import '../shared/role_scaffold.dart';
import 'kitchen_queue_page.dart';

class KitchenDashboardScreen extends StatelessWidget {
  const KitchenDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleScaffold(
      title: 'Kitchen',
      items: [
        RoleNavItem(label: 'Queue', icon: Icons.soup_kitchen, page: KitchenQueuePage()),
      ],
    );
  }
}