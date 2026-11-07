/// Server-wide switches an admin can change (`GET`/`PATCH /admin/settings`).
class AdminSettings {
  const AdminSettings({
    required this.allowRegistration,
    required this.allowRegistrationLocked,
    this.mcpEnabled = true,
    this.mcpEnabledLocked = false,
  });

  factory AdminSettings.fromJson(Map<String, dynamic> json) => AdminSettings(
    allowRegistration: json['allow_registration'] as bool,
    allowRegistrationLocked: json['allow_registration_locked'] as bool,
    // Older servers have no MCP switch: show it as on and unlocked.
    mcpEnabled: json['mcp_enabled'] as bool? ?? true,
    mcpEnabledLocked: json['mcp_enabled_locked'] as bool? ?? false,
  );

  /// Whether people can register themselves from the login screen.
  final bool allowRegistration;

  /// True when the operator set `DINATOS_ALLOW_REGISTRATION` on the server:
  /// [allowRegistration] then shows that value, and the server refuses to
  /// change it until the variable is cleared.
  final bool allowRegistrationLocked;

  /// Whether the built-in MCP server answers at `/mcp`.
  final bool mcpEnabled;

  /// True when the operator set `DINATOS_MCP_ENABLED` on the server.
  final bool mcpEnabledLocked;
}
