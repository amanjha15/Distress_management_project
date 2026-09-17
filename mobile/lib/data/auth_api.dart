import 'dart:convert';

import 'package:http/http.dart' as http;

import 'custom_http_client.dart';
import 'live_detection_api.dart' show kApiV1;

/// Matches backend `UserResponse` (app/schemas/user.py).
class SessionUser {
  const SessionUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  final int id;
  final String email;
  final String? fullName;
  final String role;

  bool get isAdmin => role == 'admin';

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      id: json['id'] as int,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      role: (json['role'] as String?) ?? 'employee',
    );
  }
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the new `/auth/request-otp`, `/auth/verify-otp` and `/auth/me`
/// routes (app/api/v1/routes/auth.py) that replaced the hardcoded mock
/// login check in AuthNotifier.
class AuthApi {
  AuthApi();

  final http.Client _client = CustomHttpClient();

  /// Returns the dev-mode OTP code (only populated when the backend's
  /// OTP_DEV_MODE is on, which is the default for local dev) so the UI can
  /// surface it directly instead of requiring a real mailbox.
  Future<String?> requestOtp(String email) async {
    final response = await _client.post(
      Uri.parse('$kApiV1/auth/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode != 200) {
      throw const AuthApiException('Failed to request a login code. Please try again.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['dev_otp'] as String?;
  }

  Future<(String token, SessionUser user)> verifyOtp({
    required String email,
    required String code,
  }) async {
    final response = await _client.post(
      Uri.parse('$kApiV1/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );
    if (response.statusCode != 200) {
      throw const AuthApiException('Invalid or expired code. Please request a new one.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    final user = SessionUser.fromJson(body['user'] as Map<String, dynamic>);
    return (token, user);
  }

  Future<SessionUser?> restoreSession(String token) async {
    final response = await _client.get(
      Uri.parse('$kApiV1/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) return null;
    return SessionUser.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
