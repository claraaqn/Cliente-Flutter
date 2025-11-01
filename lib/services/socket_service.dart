import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:cliente/services/local_storage_service.dart';

class SocketService {
  Socket? _socket;
  bool _isConnected = false;

  // Autenticação
  String? _userId;
  String? _username;

  // Stream de mensagens broadcast para listeners
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  final _messageBuffer = StringBuffer();

  // Configurações do servidor
  static const String serverHost = '10.0.2.2'; // ip para emuladores
  static const int serverPort = 8081;

  // Timeout
  static const Duration defaultTimeout = Duration(seconds: 10);

  final LocalStorageService _localStorage = LocalStorageService();

  //? handles
  Future<bool> connect() async {
    if (_isConnected) return true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkPendingMessages();
    });

    try {
      _socket = await Socket.connect(
        serverHost,
        serverPort,
        timeout: defaultTimeout,
      );
      _isConnected = true;

      _socket!.listen(
        _handleData,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: true,
      );

      debugPrint('✅ Conectado ao servidor TCP em $serverHost:$serverPort');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao conectar via TCP: $e');
      _isConnected = false;
      return false;
    }
  }

  void _handleData(List<int> data) {
    try {
      final message = utf8.decode(data);
      _messageBuffer.write(message);

      final bufferContent = _messageBuffer.toString();
      final messages = bufferContent.split('\n');

      // Processa todas menos a última (possivelmente incompleta)
      for (int i = 0; i < messages.length - 1; i++) {
        final completeMessage = messages[i].trim();
        if (completeMessage.isNotEmpty) {
          try {
            final jsonData = json.decode(completeMessage);
            _processRealTimeMessage(jsonData);
            _messageController.add(jsonData);
          } catch (e) {
            debugPrint(
                '⚠️ Erro ao decodificar JSON: $e\nMensagem: $completeMessage');
          }
        }
      }

      // Mantém a última no buffer
      _messageBuffer
        ..clear()
        ..write(messages.last);
    } catch (e) {
      debugPrint('❌ Erro ao processar dados: $e');
    }
  }

  void handleRealTimeNotifications(Map<String, dynamic> message) {
    final action = message['action'];

    switch (action) {
      case 'friend_request':
        debugPrint('🎯 Nova solicitação de amizade: ${message['message']}');
        break;
      case 'new_message':
        debugPrint('📨 Nova mensagem recebida: ${message['content']}');
        break;
      case 'user_status_change':
        debugPrint(
            '🌐 Status alterado: ${message['username']} está ${message['is_online'] ? 'online' : 'offline'}');
        break;
      case 'user_typing':
        debugPrint('✍️ ${message['username']} está digitando...');
        break;
    }
  }

  void _handleError(dynamic error) {
    debugPrint('❌ Erro na conexão TCP: $error');
    _isConnected = false;
    _messageController.add({
      'action': 'error',
      'message': 'Erro de conexão TCP: $error',
      'success': false,
    });
  }

  void _handleDisconnect() {
    debugPrint('🔌 Conexão TCP fechada');
    _isConnected = false;
  }

  //? tudo aqui cunciona - autenticação
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String publicKey,
  }) async {
    return _sendAndWaitForResponse(
      {
        'action': 'register',
        'username': username,
        'password': password,
        'public_key': publicKey,
      },
      'register_response',
    );
  }

  Future<Map<String, dynamic>> getUserSalt(String username) async {
    return _sendAndWaitForResponse(
      {
        'action': 'get_user_salt',
        'username': username,
      },
      'user_salt_response',
    );
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await _sendAndWaitForResponse(
      {
        'action': 'login',
        'username': username,
        'password': password,
      },
      'login_response',
    );

    if (response['success'] == true) {
      final userData = response['data']?['user_data'] ?? response['data'];
      if (userData != null) {
        _userId = userData['user_id']?.toString();
        _username = userData['username']?.toString() ?? username;
      }
    }

    return response;
  }

  Future<Map<String, dynamic>> sendHandshakeInit({
    required String dhePublicKey,
    required String salt,
  }) async {
    return _sendAndWaitForResponse(
      {
        'action': 'handshake_init',
        'dhe_public_key': dhePublicKey,
        'salt': salt,
      },
      'handshake_response',
    );
  }

  //? funciona - amizade
  Future<Map<String, dynamic>> sendFriendRequest(String friendUsername) async {
    return _sendAndWaitForResponse(
      {
        'action': 'send_friend_request',
        'receiver_username': friendUsername,
      },
      'send_friend_request_response',
    );
  }

  Future<Map<String, dynamic>> respondFriendRequest(
      int requestId, String responseType) async {
    return _sendAndWaitForResponse(
      {
        'action': 'respond_friend_request',
        'request_id': requestId,
        'response': responseType,
      },
      'respond_friend_request_response',
    );
  }

  Future<Map<String, dynamic>> getFriendRequests() async {
    return _sendAndWaitForResponse(
      {
        'action': 'get_friend_requests',
      },
      'get_friend_requests_response',
    );
  }

  Future<Map<String, dynamic>> getFriendsList() async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }
    return _sendAndWaitForResponse(
      {
        'action': 'get_friends_list',
      },
      'get_friends_list_response',
    );
  }

  //! Envia mensagem
  Future<Map<String, dynamic>> sendMessage(
      String receiverUsername, String content) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    if (receiverUsername.isEmpty || content.isEmpty) {
      return {'success': false, 'message': 'Dados inválidos'};
    }

    debugPrint('💬 Enviando mensagem para $receiverUsername: $content');

    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}_${_userId}';
    final messageData = {
      'sender_id': _userId,
      'sender_username': _username,
      'receiver_username': receiverUsername,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'local_id': localId,
    };

    await _localStorage.saveMessageLocally(messageData);
    debugPrint('💾 Mensagem salva localmente: $localId');

    try {
      final response = await _sendAndWaitForResponse(
        {
          'action': 'send_message',
          'receiver_username': receiverUsername,
          'content': content,
          'sender_id': _userId,
          'sender_username': _username,
          'timestamp': DateTime.now().toIso8601String(),
          'local_id': localId,
        },
        'send_message_response',
      );

      if (response['success'] == true) {
        final messageId = response['data']['message_id'];
        final isOffline = response['data']['is_offline'] == true;

        if (messageId != null) {
          await _localStorage.markMessageAsSent(localId, messageId);
        }

        debugPrint(isOffline
            ? '💾 Mensagem salva no servidor (destinatário offline)'
            : '✅ Mensagem entregue em tempo real');
      }

      return response;
    } catch (e) {
      debugPrint('❌ Erro ao enviar mensagem: $e');
      return {
        'success': false,
        'message': 'Mensagem salva localmente, erro no envio',
        'local_id': localId,
      };
    }
  }

  Future<void> checkPendingMessages() async {
    if (!_isAuthenticated() || !_isConnected) return;

    try {
      debugPrint('🔄 Verificando mensagens pendentes no servidor...');

      final response = await _sendAndWaitForResponse(
        {
          'action': 'get_pending_messages',
        },
        'get_pending_messages_response',
      );

      if (response['success'] == true) {
        final pendingMessages = response['data'] ?? [];
        debugPrint(
            '📨 ${pendingMessages.length} mensagens pendentes recebidas');

        for (final message in pendingMessages) {
          debugPrint('📨 Processando mensagem pendente: ${message['content']}');

          final newMessage = {
            'action': 'new_message',
            'id': message['id'],
            'sender_id': message['sender_id'],
            'receiver_id': message['receiver_id'],
            'content': message['content'],
            'timestamp': message['timestamp'],
            'is_delivered': true,
          };

          debugPrint('🎯 Enviando para ChatScreen: ${newMessage['content']}');

          _messageController.add(newMessage);

          try {
            await _sendAndWaitForResponse(
              {
                'action': 'confirm_message_delivery',
                'message_id': message['id'],
              },
              'confirm_delivery_response',
            );
            debugPrint('✅ Mensagem ${message['id']} confirmada');
          } catch (e) {
            debugPrint('❌ Erro ao confirmar entrega: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao verificar mensagens pendentes: $e');
    }
  }

  Future<Map<String, dynamic>> getConversationHistory(String otherUsername,
      {int limit = 50}) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    final localHistory = await _localStorage.getLocalConversationHistory(
      otherUsername,
      limit,
    );

    try {
      final serverResponse = await _sendAndWaitForResponse(
        {
          'action': 'get_conversation_history',
          'other_username': otherUsername,
          'limit': limit,
        },
        'get_conversation_history_response',
      );

      if (serverResponse['success'] == true) {
        final serverMessages = serverResponse['data'] ?? [];

        for (final message in serverMessages) {
          await _localStorage.saveReceivedMessage(message);
        }

        final allMessages = [...localHistory, ...serverMessages];
        allMessages.sort((a, b) => DateTime.parse(a['timestamp'])
            .compareTo(DateTime.parse(b['timestamp'])));

        return {
          'success': true,
          'data': allMessages.take(limit).toList(),
          'source': 'combined',
        };
      }
    } catch (e) {
      debugPrint('⚠️ Usando apenas histórico local: $e');
    }

    return {
      'success': true,
      'data': localHistory,
      'source': 'local_only',
    };
  }

  Future<Map<String, dynamic>> cleanupDeliveredMessages(
      String otherUsername) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    return _sendAndWaitForResponse(
      {
        'action': 'cleanup_delivered_messages',
        'other_username': otherUsername,
      },
      'cleanup_messages_response',
    );
  }

  Future<Map<String, dynamic>> _sendAndWaitForResponse(
    Map<String, dynamic> message,
    String expectedAction, {
    Duration timeout = defaultTimeout,
  }) async {
    if (!_isConnected && !await connect()) {
      return {
        'success': false,
        'message': 'Não foi possível conectar ao servidor TCP',
      };
    }

    try {
      final jsonMessage = json.encode(message) + '\n';
      _socket!.write(jsonMessage);

      final response = await _messageController.stream
          .firstWhere(
            (data) => data['action'] == expectedAction,
            orElse: () => {
              'action': 'timeout',
              'success': false,
              'message': 'Timeout na resposta do servidor',
            },
          )
          .timeout(timeout);

      return response;
    } catch (e) {
      return {'success': false, 'message': 'Erro ao enviar/receber: $e'};
    }
  }

  Future<Map<String, dynamic>> sendAndWaitForResponse(
    Map<String, dynamic> message,
    String expectedResponseType,
  ) async {
    return _sendAndWaitForResponse(message, expectedResponseType);
  }

  void _processRealTimeMessage(Map<String, dynamic> message) {
    final action = message['action'];

    debugPrint('🔔 Mensagem recebida no cliente: $message');

    if (action == 'new_message') {
      debugPrint(
          '🔔 Nova mensagem em tempo real. De: ${message['sender_username']}. Para: ${message['receiver_username']}');

      if (message['receiver_username'] == _username) {
        debugPrint('✅ Mensagem é para este usuário');

        _messageController.add(message);
        debugPrint('✅ Nova mensagem enviada para o stream: ${message['id']}');

        _saveMessageLocallyIfNeeded(message);
      } else {
        debugPrint('❌ Mensagem não é para este usuário');
      }
    } else if (action == 'user_typing') {
      debugPrint(
          '✍️ ${message['username']} está ${message['is_typing'] ? 'digitando' : 'parou'}');
      _messageController.add(message);
    } else if (action == 'user_online_status') {
      debugPrint(
          '🟢 Status online: ${message['username']} - ${message['is_online']}');
      _messageController.add(message);
    }
  }

  Future<void> _saveMessageLocallyIfNeeded(Map<String, dynamic> message) async {
    try {
      final messageId = message['id'];

      final existingMessages = await _localStorage.getLocalConversationHistory(
        message['sender_username'],
        100,
      );

      final isDuplicate =
          existingMessages.any((msg) => msg['server_id'] == messageId);

      if (!isDuplicate) {
        await _localStorage.saveReceivedMessage(message);
        debugPrint('💾 Mensagem em tempo real salva localmente: $messageId');
      } else {
        debugPrint('💾 Mensagem em tempo real duplicada ignorada: $messageId');
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar mensagem localmente: $e');
    }
  }

  Future<Map<String, dynamic>> checkUserOnlineStatus(String username) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }
    if (username.isEmpty) {
      return {'success': false, 'message': 'Username é obrigatório'};
    }

    debugPrint('🔍 Verificando status online de: $username');

    return _sendAndWaitForResponse(
      {
        'action': 'check_user_online_status',
        'username': username,
      },
      'user_online_status_response',
    );
  }

  //! digitação
  void sendTypingStart(String receiverUsername) {
    if (!_isAuthenticated()) return;
    _sendMessageNow({
      'action': 'typing_start',
      'receiver_username': receiverUsername,
    });
  }

  void sendTypingStop(String receiverUsername) {
    if (!_isAuthenticated()) return;
    _sendMessageNow({
      'action': 'typing_stop',
      'receiver_username': receiverUsername,
    });
  }

  //?auxiliares - ok até onde eu sei
  bool _isAuthenticated() {
    if (_userId == null) {
      debugPrint('⚠️ Ação requer autenticação. Faça login primeiro.');
      return false;
    }
    return true;
  }

  void _sendMessageNow(Map<String, dynamic> message) {
    if (_socket == null || !_isConnected) {
      debugPrint('⚠️ Socket não disponível para envio');
      return;
    }

    try {
      final jsonMessage = json.encode(message);
      debugPrint('📤 Enviando: $jsonMessage');
      _socket!.add(utf8.encode('$jsonMessage\n'));
    } catch (e) {
      debugPrint('❌ Erro ao enviar mensagem: $e');
      _messageController.add({
        'action': 'error',
        'message': 'Erro ao enviar mensagem: $e',
        'success': false
      });
    }
  }

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;

  void disconnect() {
    _socket?.close();
    _isConnected = false;
    _messageController.close();
    debugPrint('🔌 Desconectado do servidor');
  }
}
