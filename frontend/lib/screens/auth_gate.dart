import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/web_socket_service.dart';

import 'home_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();
  final _webSocketService = WebSocketService();

  bool? _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final authenticated = await _authService.restoreSession();

    if (authenticated) {
      try {
        await _webSocketService.connect();
      } catch (error) {
        debugPrint('WebSocket connection failed: $error');
      }
    }

    if (!mounted) return;

    setState(() {
      _isAuthenticated = authenticated;
    });
  }

  void _handleLoginSuccess() {
    _restoreSession();
  }

  @override
  void dispose() {
    _webSocketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isAuthenticated!) {
      return HomeScreen(webSocketEvents: _webSocketService.events);
    }

    return LoginScreen(onLoginSuccess: _handleLoginSuccess);
  }
}
