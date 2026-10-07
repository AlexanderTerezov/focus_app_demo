import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import '../models/user.dart';

class AuthService {
  final ApiService _api = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      body: {'identifier': identifier, 'password': password},
    );

    if (response.statusCode != 200) {
      throw Exception(
        _getErrorMessage(response.body, 'Invalid username/email or password.'),
      );
    }

    final data = jsonDecode(response.body);

    await _saveTokens(data);

    return data;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/register',
      body: {'email': email, 'username': username, 'password': password},
    );

    if (response.statusCode != 201) {
      throw Exception(
        _getErrorMessage(
          response.body,
          'Unable to create your account. Please try again.',
        ),
      );
    }

    return jsonDecode(response.body);
  }

  Future<User> getMe() async {
    final accessToken = await getAccessToken();

    if (accessToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _api.get('/me', accessToken: accessToken);

    if (response.statusCode != 200) {
      throw Exception('Failed to load user');
    }

    final data = jsonDecode(response.body);

    return User.fromJson(data);
  }

  Future<bool> restoreSession() async {
    final accessToken = await getAccessToken();

    if (accessToken == null) {
      return false;
    }

    try {
      await getMe();
      return true;
    } catch (_) {
      return await refreshAccessToken();
    }
  }

  Future<bool> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();

    if (refreshToken == null) {
      return false;
    }

    try {
      final response = await _api.post(
        '/auth/refresh',
        body: {'refresh_token': refreshToken},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        await logout();
        return false;
      }

      await _saveTokens(data);

      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<String?> getAccessToken() {
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.write(key: _accessTokenKey, value: data['access_token']);

    await _storage.write(key: _refreshTokenKey, value: data['refresh_token']);
  }

  Future<void> logout() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  String _getErrorMessage(String responseBody, String fallback) {
    try {
      final data = jsonDecode(responseBody);

      if (data is Map<String, dynamic> && data['error'] is String) {
        return data['error'];
      }
    } catch (_) {
      // Response wasn't valid JSON.
    }

    return fallback;
  }
}
