/// One of the caller's API keys as the list shows it -- never the key itself,
/// only its name and last few characters. See `POST /api-keys`.
class ApiKeySummary {
  const ApiKeySummary({
    required this.id,
    required this.name,
    required this.suffix,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory ApiKeySummary.fromJson(Map<String, dynamic> json) => ApiKeySummary(
    id: json['id'] as int,
    name: json['name'] as String,
    suffix: json['suffix'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    lastUsedAt: json['last_used_at'] == null
        ? null
        : DateTime.parse(json['last_used_at'] as String),
  );

  final int id;
  final String name;
  final String suffix;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// The response to creating a key: the only time the key is ever sent.
class CreatedApiKey {
  const CreatedApiKey({required this.summary, required this.key});

  factory CreatedApiKey.fromJson(Map<String, dynamic> json) =>
      CreatedApiKey(summary: ApiKeySummary.fromJson(json), key: json['key'] as String);

  final ApiKeySummary summary;
  final String key;
}
