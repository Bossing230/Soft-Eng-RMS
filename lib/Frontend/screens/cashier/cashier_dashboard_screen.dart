import 'package:flutter/material.dart';
import 'package:rms/Frontend/screens/shared/order_management_page.dart';
import '../shared/role_scaffold.dart';
import '../shared/tables_management_page.dart';
import 'cashier_summary_page.dart';
import 'pos_page.dart';

class CashierDashboardScreen extends StatelessWidget {
  const CashierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleScaffold(
      title: 'Cashier',
      items: [
        RoleNavItem(label: 'POS', icon: Icons.point_of_sale, page: PosPage(), pageTitle: 'Point of Sale'),
        RoleNavItem(label: 'Orders', icon: Icons.receipt_long, page: OrderManagementPage()),
        RoleNavItem(label: 'Tables', icon: Icons.table_bar, page: TablesManagementPage()),
        RoleNavItem(
          label: 'Summary',
          icon: Icons.grid_view,
          page: CashierSummaryPage(),
          pageTitle: 'Cashier Dashboard',
        ),
      ],
    );
  }
}