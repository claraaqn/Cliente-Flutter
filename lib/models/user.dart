class User {
  final int id;
  final String username;
  final DateTime createdAt;

  User({required this.id, required this.username, required this.createdAt});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
