class Message {
  final int? id;
  final int senderId;
  final int receiverId;
  final String content;
  final DateTime timestamp;
  final bool isDelivered;
  final bool isMine;
  final bool hasError;
  final String? localId;
  final bool isSentToServer; 

  Message({
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    this.isDelivered = false,
    this.isMine = false,
    this.hasError = false,
    this.localId, 
    this.isSentToServer = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    int? safeParseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      if (value is num) return value.toInt();
      return null;
    }

    String safeParseString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      return value.toString();
    }

    DateTime safeParseDateTime(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    bool safeParseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) {
        return value.toLowerCase() == 'true' || value == '1';
      }
      return false;
    }

    return Message(
      id: safeParseInt(json['id']),
      senderId: safeParseInt(json['sender_id']) ?? 0,
      receiverId: safeParseInt(json['receiver_id']) ?? 0,
      content: safeParseString(json['content']),
      timestamp: safeParseDateTime(json['timestamp']),
      isDelivered: safeParseBool(json['is_delivered'] ?? true),
      localId: safeParseString(json['local_id']), 
      isSentToServer: safeParseBool(json['is_sent_to_server'] ?? false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'is_delivered': isDelivered,
      'local_id': localId,
      'is_sent_to_server': isSentToServer, 
    };
  }

  Message copyWith({
    int? id,
    int? senderId,
    int? receiverId,
    String? content,
    DateTime? timestamp,
    bool? isDelivered,
    bool? isMine,
    bool? hasError,
    String? localId,
    bool? isSentToServer, 
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isDelivered: isDelivered ?? this.isDelivered,
      isMine: isMine ?? this.isMine,
      hasError: hasError ?? this.hasError,
      localId: localId ?? this.localId,
      isSentToServer: isSentToServer ?? this.isSentToServer,
    );
  }
}
