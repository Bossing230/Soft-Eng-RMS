import 'package:flutter/material.dart';
import 'package:rms/Frontend/core/routes/app_router.dart';
import 'package:rms/Frontend/core/theme/app_theme.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/screens/auth/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RmsApp());
}

class RmsApp extends StatefulWidget {
  const RmsApp({super.key});

  @override
  State<RmsApp> createState() => _RmsAppState();
}

class _RmsAppState extends State<RmsApp> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await SessionManager().loadFromStorage();
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final session = SessionManager();
    final home = session.isLoggedIn && session.role != null
        ? AppRouter.dashboardForRole(session.role!)
        : const LoginScreen();

    return MaterialApp(
      title: 'Restaurant Management System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: home,
    );
  }
}