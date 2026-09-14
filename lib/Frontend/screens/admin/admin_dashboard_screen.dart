import 'package:flutter/material.dart';
import 'package:rms/Frontend/screens/manager/menu_management_page.dart';
import 'package:rms/Frontend/screens/shared/report_page.dart';
import '../shared/role_scaffold.dart';
import '../shared/rich_overview_page.dart';
import '../manager/inventory_management_page.dart';
import 'employee_management_page.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleScaffold(
      title: 'Administrator',
      items: const [
        RoleNavItem(label: 'Overview', icon: Icons.dashboard, page: RichOverviewPage(isAdmin: true)),
        RoleNavItem(label: 'Employees', icon: Icons.people, page: EmployeeManagementPage()),
        RoleNavItem(label: 'Menu', icon: Icons.restaurant_menu, page: MenuManagementPage()),
        RoleNavItem(label: 'Inventory', icon: Icons.inventory_2, page: InventoryManagementPage()),
        RoleNavItem(label: 'Reports', icon: Icons.bar_chart, page: ReportsPage()),
      ],
    );
  }
}