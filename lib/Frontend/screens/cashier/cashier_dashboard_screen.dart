import 'package:flutter/material.dart';
import 'package:rms/Frontend/screens/shared/order_management_page.dart';
import '../shared/role_scaffold.dart';
import '../shared/dashboard_overview_page.dart';
import '../shared/reservation_page.dart';
import 'pos_page.dart';

class CashierDashboardScreen extends StatelessWidget {
  const CashierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleScaffold(
      title: 'Cashier',
      items: [
        RoleNavItem(label: 'Overview', icon: Icons.dashboard, page: DashboardOverviewPage()),
        RoleNavItem(label: 'New Order', icon: Icons.point_of_sale, page: PosPage()),
        RoleNavItem(label: 'Orders', icon: Icons.receipt_long, page: OrderManagementPage()),
        RoleNavItem(label: 'Reservations', icon: Icons.event_seat, page: ReservationPage()),
      ],
    );
  }
}