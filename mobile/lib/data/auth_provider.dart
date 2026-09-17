import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_api.dart';

/// Real Email + OTP session state, backed by the DB-backed opaque bearer
/// token issued by POST /auth/verify-otp (see app/services/otp_service.py).
/// Replaces the old hardcoded admin@akcm.com / Admin@123 mock check.
class AuthState {
  const AuthState({
    required this.isAuthenticated,
    this.rememberedEmail,
    this.token,
    this.user,
    this.isRestoring = true,
  });

  final bool isAuthenticated;
  final String? rememberedEmail;
  final String? token;
  final SessionUser? user;

  /// True while the app is checking a saved token against /auth/me on
  /// launch -- the router should hold on the splash/login route until this
  /// settles, so an already-logged-in user isn't bounced to /login first.
  final bool isRestoring;

  AuthState copyWith({
    bool? isAuthenticated,
    String? rememberedEmail,
    String? token,
    SessionUser? user,
    bool? isRestoring,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      rememberedEmail: rememberedEmail ?? this.rememberedEmail,
      token: token ?? this.token,
      user: user ?? this.user,
      isRestoring: isRestoring ?? this.isRestoring,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  static const _tokenKey = 'auth_token';
  static const _rememberedEmailKey = 'rememberedEmail';

  final _api = AuthApi();

  @override
  AuthState build() {
    _restore();
    return const AuthState(isAuthenticated: false, isRestoring: true);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedEmail = prefs.getString(_rememberedEmailKey);
    final token = prefs.getString(_tokenKey);

    if (token == null) {
      state = AuthState(
        isAuthenticated: false,
        rememberedEmail: rememberedEmail,
        isRestoring: false,
      );
      return;
    }

    final user = await _api.restoreSession(token);
    if (user == null) {
      await prefs.remove(_tokenKey);
      state = AuthState(
        isAuthenticated: false,
        rememberedEmail: rememberedEmail,
        isRestoring: false,
      );
      return;
    }

    state = AuthState(
      isAuthenticated: true,
      rememberedEmail: rememberedEmail,
      token: token,
      user: user,
      isRestoring: false,
    );
  }

  /// Step 1 of Email + OTP login. Returns the dev-mode OTP so the UI can
  /// surface it (no real mailbox wired up yet -- see otp_service.py).
  Future<String?> requestOtp(String email) => _api.requestOtp(email);

  /// Step 2: verify the code, persist the session token, and mark the user
  /// authenticated.
  Future<bool> verifyOtp({
    required String email,
    required String code,
    required bool rememberMe,
  }) async {
    final (token, user) = await _api.verifyOtp(email: email, code: code);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (rememberMe) {
      await prefs.setString(_rememberedEmailKey, email);
    } else {
      await prefs.remove(_rememberedEmailKey);
    }

    state = AuthState(
      isAuthenticated: true,
      rememberedEmail: rememberMe ? email : null,
      token: token,
      user: user,
      isRestoring: false,
    );
    return true;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    state = AuthState(
      isAuthenticated: false,
      rememberedEmail: state.rememberedEmail,
      isRestoring: false,
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
