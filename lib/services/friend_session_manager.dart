import 'dart:math';
import 'package:flutter/foundation.dart';

class FriendSession {
  int messageCount = 0;
  DateTime startTime;

  final int maxMessages;
  final int maxDurationMinutes;

  FriendSession({
    required this.maxMessages,
    required this.maxDurationMinutes,
  }) : startTime = DateTime.now();
}

class FriendSessionManager {
  static final FriendSessionManager _instance =
      FriendSessionManager._internal();
  factory FriendSessionManager() => _instance;
  FriendSessionManager._internal();

  final Map<int, FriendSession> _sessions = {};
  final Random _random = Random();

  static const int _minMsg = 3;
  static const int _maxMsg = 5;
  static const int _minTime = 1;
  static const int _maxTime = 2;

  bool shouldRotate(int idFriendship) {
    if (!_sessions.containsKey(idFriendship)) {
      _startSession(idFriendship);
      return false;
    }

    final session = _sessions[idFriendship]!;
    final duration = DateTime.now().difference(session.startTime).inMinutes;

    bool countExpired = session.messageCount >= session.maxMessages;
    bool timeExpired = duration >= session.maxDurationMinutes;

    if (countExpired || timeExpired) {
      return true;
    }
    return false;
  }

  // Incrementa contador após envio
  void incrementMessageCount(int friendId) {
    if (!_sessions.containsKey(friendId)) {
      _startSession(friendId);
    }
    _sessions[friendId]!.messageCount++;
    final s = _sessions[friendId]!;
    debugPrint("Amigo $friendId: ${s.messageCount}/${s.maxMessages} msgs");
  }

  // Reinicia a sessão (chamado após Handshake com sucesso)
  void resetSession(int friendId) {
    _startSession(friendId);
    debugPrint(
        "Sessão com amigo $friendId resetada. Novos limites definidos.");
  }

  void _startSession(int friendId) {
    int maxMsg = _minMsg + _random.nextInt(_maxMsg - _minMsg + 1);
    int maxTime = _minTime + _random.nextInt(_maxTime - _minTime + 1);

    _sessions[friendId] = FriendSession(
      maxMessages: maxMsg,
      maxDurationMinutes: maxTime,
    );
  }
}
