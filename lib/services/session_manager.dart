import 'dart:math';
import 'package:flutter/foundation.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();

  factory SessionManager() {
    return _instance;
  }

  SessionManager._internal() {
    _resetLimits();
    _sessionStartTime = DateTime.now();
  }

  final Random _random = Random();

  late int _maxMessages;
  late int _maxDurationMinutes;

  int _messageCount = 0;
  DateTime? _sessionStartTime;

  static const int _minMsg = 3;
  static const int _maxMsg = 5;
  static const int _minTime = 1; 
  static const int _maxTime = 2;

  void startSession() {
    _sessionStartTime = DateTime.now();
    _messageCount = 0;
    _resetLimits();
  }

  void incrementMessageCount() {
    _messageCount++;
  }

  bool shouldRenegotiate() {
    if (_sessionStartTime == null) return false;

    final duration = DateTime.now().difference(_sessionStartTime!).inMinutes;

    bool timeExpired = duration >= _maxDurationMinutes;
    bool countExpired = _messageCount >= _maxMessages;

    if (timeExpired || countExpired) {
      debugPrint(
          "Sessão expirada! (Tempo: $timeExpired, Msgs: $countExpired)");
      return true;
    }
    return false;
  }

  void _resetLimits() {
    _maxMessages = _minMsg + _random.nextInt(_maxMsg - _minMsg + 1);
    _maxDurationMinutes = _minTime + _random.nextInt(_maxTime - _minTime + 1);
  }
}
