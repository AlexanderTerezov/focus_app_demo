import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8080';

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: body == null ? null : jsonEncode(body),
    );
  }

  Future<http.Response> get(String path, {String? accessToken}) {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
    );
  }
}
