import 'dart:convert';

import '../models/focus_session.dart';
import 'api_service.dart';
import 'auth_service.dart';

class FocusSessionService {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  Future<FocusSession> createFocusSession({
    required int studyDurationSeconds,
    required int shortBreakDurationSeconds,
    required int longBreakDurationSeconds,
    required int sessionsUntilLongBreak,
    required bool isInfinite,
  }) async {
    final accessToken = await _authService.getAccessToken();

    if (accessToken == null) {
      throw Exception('You are not logged in.');
    }

    final response = await _apiService.post(
      '/focus-sessions',
      accessToken: accessToken,
      body: {
        'study_duration_seconds': studyDurationSeconds,
        'short_break_duration_seconds': shortBreakDurationSeconds,
        'long_break_duration_seconds': longBreakDurationSeconds,
        'sessions_until_long_break': sessionsUntilLongBreak,
        'is_infinite': isInfinite,
      },
    );

    if (response.statusCode != 201) {
      throw Exception('Unable to start focus session.');
    }

    return FocusSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> completeFocusSession({
    required int sessionId,
  }) async {
    final accessToken = await _authService.getAccessToken();

    if (accessToken == null) {
      throw Exception('You are not logged in.');
    }

    final response = await _apiService.post(
      '/focus-sessions/$sessionId/complete',
      accessToken: accessToken,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to complete focus session. '
        'Status: ${response.statusCode}, Body: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> endFocusSession({required int sessionId}) async {
    final accessToken = await _authService.getAccessToken();

    if (accessToken == null) {
      throw Exception('You are not logged in.');
    }

    final response = await _apiService.post(
      '/focus-sessions/$sessionId/end',
      accessToken: accessToken,
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to end focus session.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<FocusSession?> getActiveFocusSession() async {
    final accessToken = await _authService.getAccessToken();

    if (accessToken == null) {
      throw Exception('You are not logged in.');
    }

    final response = await _apiService.get(
      '/focus-sessions/active',
      accessToken: accessToken,
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw Exception('Unable to get active focus session.');
    }

    return FocusSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
