class ChatUser {
  final String username;
  final bool isOnline;

  ChatUser({
    required this.username,
    required this.isOnline,
  });
}

class ChatMessage {
  final String from;
  final String content;
  final DateTime? timestamp;

  ChatMessage({required this.from, required this.content, this.timestamp,});
}
