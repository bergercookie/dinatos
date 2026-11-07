/// Server-wide options an admin can change (`GET`/`PATCH /admin/settings`).
class AdminSettings {
  const AdminSettings({required this.allowRegistration, required this.allowRegistrationLocked});

  factory AdminSettings.fromJson(Map<String, dynamic> json) => AdminSettings(
    allowRegistration: json['allow_registration'] as bool,
    allowRegistrationLocked: json['allow_registration_locked'] as bool,
  );

  /// Whether people can register themselves from the login screen.
  final bool allowRegistration;

  /// True when the operator set `DINATOS_ALLOW_REGISTRATION` on the server:
  /// [allowRegistration] then shows that value, and the server refuses to
  /// change it until the variable is cleared.
  final bool allowRegistrationLocked;
}
