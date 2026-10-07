import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import 'auth_service.dart';

class WebSocketService {
  static const String baseUrl = 'ws://localhost:8080';

  final AuthService _authService = AuthService();

  IOWebSocketChannel? _channel;

  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  Future<void> connect() async {
    if (_channel != null) {
      return;
    }

    final accessToken = await _authService.getAccessToken();

    if (accessToken == null) {
      throw Exception('You are not logged in.');
    }

    _channel = IOWebSocketChannel.connect(
      Uri.parse('$baseUrl/ws'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    await _channel!.ready;

    debugPrint('WebSocket connected.');

    _channel!.stream.listen(
      (message) {
        try {
          final event = jsonDecode(message as String) as Map<String, dynamic>;

          _eventController.add(event);
        } catch (error) {
          debugPrint('Invalid WebSocket message: $error');
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
      onDone: () {
        debugPrint('WebSocket disconnected.');
        _channel = null;
      },
    );
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
  }
}
