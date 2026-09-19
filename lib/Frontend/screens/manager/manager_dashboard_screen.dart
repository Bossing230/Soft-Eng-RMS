import 'package:flutter/material.dart';
import 'package:rms/Frontend/screens/manager/menu_management_page.dart';
import 'package:rms/Frontend/screens/shared/order_maangement_page.dart';
import 'package:rms/Frontend/screens/shared/report_page.dart';
import '../shared/role_scaffold.dart';
import 'manager_overview_page.dart';
import 'inventory_management_page.dart';
import '../shared/reservation_page.dart';

class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleScaffold(
      title: 'Manager',
      items: [
        RoleNavItem(label: 'Overview', icon: Icons.dashboard, page: ManagerOverviewPage()),
        RoleNavItem(label: 'Orders', icon: Icons.receipt_long, page: OrderManagementPage(canForceCancel: true)),
        RoleNavItem(label: 'Reservations', icon: Icons.event_seat, page: ReservationPage()),
        RoleNavItem(label: 'Menu', icon: Icons.restaurant_menu, page: MenuManagementPage()),
        RoleNavItem(label: 'Inventory', icon: Icons.inventory_2, page: InventoryManagementPage()),
        RoleNavItem(label: 'Reports', icon: Icons.bar_chart, page: ReportsPage()),
      ],
    );
  }
}