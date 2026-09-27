class User {
  const User({required this.id, required this.email, required this.isAdmin});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    email: json['email'] as String,
    isAdmin: json['is_admin'] as bool,
  );

  final int id;
  final String email;
  final bool isAdmin;
}
