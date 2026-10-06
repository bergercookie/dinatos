import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user.dart';
import '../api_exception.dart';
import '../dio_provider.dart';
import '../local/local_mode.dart';
import 'auth_state.dart';
import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(dioProvider),
    ref.watch(tokenStorageProvider),
    local: ref.watch(localModeProvider),
  );
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._dio, this._tokenStorage, {this.local = false}) : super(const AuthUnknown()) {
    // Attaches directly to the `Dio` instance this notifier already holds,
    // rather than as an interceptor built from `dioProvider`'s own `ref`:
    // that would need to read `authNotifierProvider` back (for the token,
    // and to react to a 401), and `authNotifierProvider` depends on
    // `dioProvider` -- a cycle Riverpod rejects with a
    // `CircularDependencyError`. See dio_provider.dart's doc comment.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final current = state;
          if (current is AuthAuthenticated) {
            options.headers['Authorization'] = 'Bearer ${current.token}';
          }
          handler.next(options);
        },
        onError: (err, handler) {
          if (err.response?.statusCode == 401) handleUnauthorized();
          handler.next(err);
        },
      ),
    );
    _bootstrap();
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Local (no-server) mode: there is no account to log in to, the person is
  /// simply "this device".
  final bool local;

  /// On startup: a stored token might still be valid (it hasn't hit its
  /// expiry or been revoked -- logged out from here, or from another
  /// device/tab, since a session is per-login, not per-account).
  /// `GET /auth/me` is both the check and how the signed-in user is fetched.
  ///
  /// Every state change here is guarded by `state is AuthUnknown`: this
  /// notifier is recreated whenever the server URL changes (it watches
  /// [dioProvider], which watches [serverUrlProvider]), so a switch to a new
  /// server fires off a fresh, unawaited bootstrap at the same moment the
  /// login/profile screen that triggered the switch is about to call
  /// [login] on this same fresh instance. Without the guard, whichever of
  /// the two finishes last would win, and a slow bootstrap resolving after
  /// a fast, successful login could stomp `AuthAuthenticated` back to
  /// `AuthUnauthenticated`. Once anything else has already settled `state`,
  /// bootstrap's own opinion no longer matters.
  Future<void> _bootstrap() async {
    if (local) {
      state = const AuthAuthenticated(
        token: 'local',
        user: User(id: 1, email: 'this device', isAdmin: false),
      );
      return;
    }
    final token = await _tokenStorage.read();
    if (token == null) {
      if (state is AuthUnknown) state = const AuthUnauthenticated();
      return;
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (state is AuthUnknown) {
        state = AuthAuthenticated(token: token, user: User.fromJson(response.data!));
      }
    } on DioException {
      await _tokenStorage.clear();
      if (state is AuthUnknown) state = const AuthUnauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = response.data!['access_token'] as String;
      await _completeLogin(token);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<void> register(String email, String password) async {
    try {
      await _dio.post<void>('/auth/register', data: {'email': email, 'password': password});
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
    // Registering doesn't itself return a token -- log in right after with
    // the same credentials, same as a person would from the login screen.
    await login(email, password);
  }

  Future<void> _completeLogin(String token) async {
    await _tokenStorage.write(token);
    final response = await _dio.get<Map<String, dynamic>>(
      '/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    state = AuthAuthenticated(token: token, user: User.fromJson(response.data!));
  }

  /// Revokes this session server-side, then clears the token locally
  /// regardless of whether that call actually succeeded -- if the backend
  /// is unreachable, the person still expects "logout" to log them out of
  /// *this* device; the token being technically still valid server-side
  /// until it expires is a lesser problem than being stuck logged in.
  Future<void> logout() async {
    if (local) return; // nobody is logged in
    try {
      await _dio.post<void>('/auth/logout');
    } on DioException {
      // Best-effort: see above.
    }
    await _tokenStorage.clear();
    state = const AuthUnauthenticated();
  }

  /// Called by the Dio interceptor on any 401: the token expired or was
  /// otherwise rejected mid-session. Same end state as [logout], just not
  /// user-initiated.
  void handleUnauthorized() {
    if (state is AuthAuthenticated) {
      unawaited(_tokenStorage.clear());
      state = const AuthUnauthenticated();
    }
  }
}
