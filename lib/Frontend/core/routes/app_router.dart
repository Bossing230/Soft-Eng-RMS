import 'package:flutter/material.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/screens/admin/admin_dashboard_screen.dart';
import 'package:rms/Frontend/screens/cashier/cashier_dashboard_screen.dart';
import 'package:rms/Frontend/screens/kitchen/kitchen_dashboard_screen.dart';
import 'package:rms/Frontend/screens/manager/manager_dashboard_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../constants/app_constants.dart';

/// Central place that decides which Flutter dashboard a role lands on
/// after authenticating, per the "automatic redirect based on role"
/// requirement.
class AppRouter {
  static Widget dashboardForRole(String role) {
    switch (role) {
      case AppConstants.roleAdmin:
        return const AdminDashboardScreen();
      case AppConstants.roleManager:
        return const ManagerDashboardScreen();
      case AppConstants.roleCashier:
        return const CashierDashboardScreen();
      case AppConstants.roleKitchen:
        return const KitchenDashboardScreen();
      default:
        return const LoginScreen();
    }
  }

  static void goToRoleDashboard(BuildContext context) {
    final role = SessionManager().role;
    if (role == null) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => dashboardForRole(role)),
      (r) => false,
    );
  }

  static void goToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }
}