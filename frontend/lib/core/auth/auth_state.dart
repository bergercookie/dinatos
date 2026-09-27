import '../../models/user.dart';

/// - [AuthUnknown]: startup, before the stored token (if any) has been
///   checked against `GET /auth/me`.
/// - [AuthUnauthenticated]: no valid token -- never logged in, logged out
///   client-side, the token expired, or the server rejected it (401).
/// - [AuthAuthenticated]: holds the token every request attaches, and the
///   user it belongs to.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.token, required this.user});

  final String token;
  final User user;
}
