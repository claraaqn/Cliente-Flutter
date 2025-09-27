class Friend {
  final int id;
  final String username;
  final DateTime createdAt;
  final bool isOnline;
  final DateTime? lastSeen;

  Friend({
    required this.id,
    required this.username,
    required this.createdAt,
    required this.isOnline,
    this.lastSeen,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    final isOnlineRaw = json['is_online'];
    final isOnline = (isOnlineRaw == 1) ||
        (isOnlineRaw == true) ||
        (isOnlineRaw == '1') ||
        (isOnlineRaw == 'true');

    return Friend(
      id: json['id'],
      username: json['username'],
      createdAt: DateTime.parse(json['created_at']),
      isOnline: isOnline,
      lastSeen:
          json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
    );
  }
}

class FriendRequest {
  final int id;
  final String username;
  final String direction;
  final DateTime createdAt;

  FriendRequest({
    required this.id,
    required this.username,
    required this.direction,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      direction: json['direction'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}
