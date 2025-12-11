import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:cliente/services/crypto_service.dart';
import 'package:cliente/services/messagecrypo_servece.dart';
import 'package:flutter/widgets.dart';
import 'package:cliente/services/local_storage_service.dart';
import 'package:uuid/uuid.dart';

class SocketService {
  Socket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Autenticação
  String? _userId;
  String? _username;

  // Criptografia
  final CryptoService _crypto = CryptoService();
  final MessageCryptoService _messageCrypto = MessageCryptoService();
  bool _isEncryptionEnabled = false;

  // Stream de mensagens broadcast para listeners
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  final _messageBuffer = StringBuffer();

  // Configurações do servidor
  static const String serverHost = '10.0.2.2'; // ip para emuladores
  static const int serverPort = 8081;

  // Timeout
  static const Duration defaultTimeout = Duration(seconds: 10);

  final LocalStorageService _localStorage = LocalStorageService();

  int? _authenticatedUserId;
  bool get isAuthenticated => _authenticatedUserId != null;

  void setAuthenticatedUser({required int userId, required String username}) {
    _authenticatedUserId = userId;
    debugPrint('SocketService - Usuário autenticado: $username (ID: $userId)');
  }

  void clearAuthentication() {
    _authenticatedUserId = null;
    debugPrint('SocketService - Autenticação limpa');
  }

  void setSessionKeysDirectly({
    required String sessionId,
    required Uint8List encryptionKey,
    required Uint8List hmacKey,
  }) {
    // CONFIGURA AS CHAVES NO MessageCryptoService
    _messageCrypto.setSessionKeys(
      encryptionKey: encryptionKey,
      hmacKey: hmacKey,
    );

    _isEncryptionEnabled = true;
  }

  //? handles
  Future<bool> connect() async {
    // Já conectado → nada a fazer
    if (_isConnected) return true;

    // Já existe uma tentativa em andamento → espere ela terminar
    if (_isConnecting) {
      debugPrint("⏳ Conexão já em andamento...");
      while (_isConnecting) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _isConnected;
    }

    _isConnecting = true;

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

      debugPrint('Conectado ao servidor TCP em $serverHost:$serverPort');

      return true;
    } catch (e) {
      debugPrint('Erro ao conectar via TCP: $e');
      _isConnected = false;
      return false;
    } finally {
      _isConnecting = false;
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

      _messageBuffer
        ..clear()
        ..write(messages.last);
    } catch (e) {
      debugPrint('Erro ao processar dados: $e');
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
    debugPrint('Erro na conexão TCP: $error');
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
    disableEncryption();
    _crypto.clearSessionKeys();
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
    // Apenas envia o handshake, o processamento fica no HandshakeService
    final response = await _sendAndWaitForResponse(
      {
        'action': 'handshake_init',
        'dhe_public_key': dhePublicKey,
        'salt': salt,
        'request_id': DateTime.now().millisecondsSinceEpoch.toString(),
      },
      'handshake_response',
    );

    if (response['success'] == true) {
      enableEncryption();
    }

    return response;
  }

  //? funciona - amizade
  Future<Map<String, dynamic>> sendFriendRequest(
      String friendUsername, int userId) async {
    final keys = await _crypto.generateDHEKeyPair();
    final pubA = keys["publicKey"];
    final privA = keys["privateKey"];

    await _localStorage.saveFriendRequestKeySender(userId, privA!);

    return _sendAndWaitForResponse(
      {
        'action': 'send_friend_request',
        'sender_id': _userId,
        'receiver_username': friendUsername,
        "dhe_public_sender": pubA
      },
      'send_friend_request_response',
    );
  }

  Future<Map<String, dynamic>> respondFriendRequest(
      int reciverId, String responseType, int userId) async {
    final keys = await _crypto.generateDHEKeyPair();
    final pubB = keys["publicKey"];
    final privB = keys["privateKey"];

    final local = LocalStorageService();
    await local.saveFriendRequestKeyReceiver(reciverId, privB!);

    return _sendAndWaitForResponse(
      {
        'action': 'respond_friend_request',
        'reciverId': reciverId,
        'response': responseType,
        "dhe_public": pubB
      },
      'respond_friend_request_response',
    );
  }

  Future<Future<Map<String, dynamic>>> handshakeFriends(
      int senderId, String receiverPub, int reciverId) async {
    debugPrint('Começando HandShake');

    final privA =
        await _localStorage.getFriendRequestPrivateKeySender(senderId);

    final sessionSalt = _crypto.generateSalt();
    final sessionId = const Uuid().v4();

    final sharedSecret = _crypto.computeSharedSecretBytes(
      ownPrivateBase64: privA!,
      peerPublicBase64: receiverPub,
    );

    final sessionKeys = await _crypto.deriveKeysFromSharedSecret(
      sharedSecret: await sharedSecret,
      saltBase64: sessionSalt,
      info: utf8.encode('session_keys_v1'),
    );

    final encryptionKey = sessionKeys['encryption'];
    final hmacKey = sessionKeys['hmac'];

    String _convertKey(dynamic key) {
      if (key is List<int>) {
        return base64Encode(Uint8List.fromList(key));
      } else if (key is String) {
        return key;
      } else {
        return key.toString();
      }
    }

    debugPrint('Handshake realizado - Chaves de sessão geradas');

    return _sendAndWaitForResponse({
      "action": "handshake_complete",
      "reciverId": reciverId,
      "session_id": sessionId,
      "salt": sessionSalt,
      "encryption_key":_convertKey(encryptionKey),
      "hmac_key": _convertKey(hmacKey),
      "shared_secret": base64Encode(await sharedSecret),
    }, "handshake_finalizado");
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
    debugPrint('Mensagem salva localmente: $localId');

    try {
      // Prepara a mensagem para envio (criptografada ou não)
      final Map<String, dynamic> messageToSend;

      if (_isEncryptionEnabled) {
        // Criptografa a mensagem
        final plainMessage = {
          'action': 'send_message',
          'receiver_username': receiverUsername,
          'content': content,
          'sender_id': _userId,
          'sender_username': _username,
          'timestamp': DateTime.now().toIso8601String(),
          'local_id': localId,
        };

        final encryptedMessage =
            await _crypto.encryptMessage(json.encode(plainMessage));
        messageToSend = {
          'action': 'encrypted_message',
          ...encryptedMessage,
        };
      } else {
        // Mensagem não criptografada (antes do handshake)
        messageToSend = {
          'action': 'send_message',
          'receiver_username': receiverUsername,
          'content': content,
          'sender_id': _userId,
          'sender_username': _username,
          'timestamp': DateTime.now().toIso8601String(),
          'local_id': localId,
        };
      }

      final response = await _sendAndWaitForResponse(
        messageToSend,
        'send_message_response',
      );

      if (response['success'] == true) {
        final messageId = response['data']['message_id'];
        final isOffline = response['data']['is_offline'] == true;

        if (messageId != null) {
          await _localStorage.markMessageAsSent(localId, messageId);
        }

        debugPrint(isOffline
            ? 'Mensagem salva no servidor (destinatário offline)'
            : 'Mensagem entregue em tempo real');
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

          _messageController.add(newMessage);

          try {
            await _sendAndWaitForResponse(
              {
                'action': 'confirm_message_delivery',
                'message_id': message['id'],
              },
              'confirm_delivery_response',
            );
            debugPrint('Mensagem ${message['id']} confirmada');
          } catch (e) {
            debugPrint('Erro ao confirmar entrega: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar mensagens pendentes: $e');
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
      // Prepara a requisição (criptografada ou não)
      final Map<String, dynamic> request;

      if (_isEncryptionEnabled) {
        final plainRequest = {
          'action': 'get_conversation_history',
          'other_username': otherUsername,
          'limit': limit,
        };

        final encrypted =
            await _crypto.encryptMessage(json.encode(plainRequest));
        request = {
          'action': 'encrypted_message',
          ...encrypted,
        };
      } else {
        request = {
          'action': 'get_conversation_history',
          'other_username': otherUsername,
          'limit': limit,
        };
      }

      final serverResponse = await _sendAndWaitForResponse(
        request,
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
      final jsonMessage = '${json.encode(message)}\n';
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

  Future<void> _processRealTimeMessage(Map<String, dynamic> message) async {
    try {
      // Verifica se é uma mensagem criptografada
      if (_isEncryptionEnabled && _isEncryptedMessage(message)) {
        final decryptedMessage = _decryptReceivedMessage(message);
        _messageController.add(await decryptedMessage);
      } else {
        _messageController.add(message);
      }
    } catch (e) {
      debugPrint('Erro ao processar mensagem: $e');
      // Envia mensagem de erro
      _messageController.add({
        'action': 'error',
        'message': 'Erro ao processar mensagem: $e',
        'success': false,
      });
    }
  }

//! criptografia
  bool _isEncryptedMessage(Map<String, dynamic> message) {
    return message.containsKey('ciphertext') &&
        message.containsKey('hmac') &&
        message['action'] != 'handshake_response'; // Exceção para handshake
  }

  Future<Map<String, dynamic>> _decryptReceivedMessage(
      Map<String, dynamic> encryptedMessage) async {
    try {
      if (!_messageCrypto.isReady) {
        throw Exception(
            'MessageCryptoService não está pronto - chaves não configuradas');
      }

      final encryptedPayload = {
        'ciphertext': encryptedMessage['ciphertext'].toString(),
        'hmac': encryptedMessage['hmac'].toString(),
      };

      final decryptedJson =
          await _messageCrypto.decryptMessage(encryptedPayload);
      final decryptedMessage = json.decode(decryptedJson);

      return decryptedMessage;
    } catch (e) {
      debugPrint('Erro ao descriptografar mensagem: $e');
      rethrow;
    }
  }

  void enableEncryption() {
    _isEncryptionEnabled = true;
  }

  void disableEncryption() {
    _isEncryptionEnabled = false;
    debugPrint('🛡️ Criptografia de mensagens DESATIVADA');
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
        debugPrint('Mensagem em tempo real salva localmente: $messageId');
      } else {
        debugPrint('Mensagem em tempo real duplicada ignorada: $messageId');
      }
    } catch (e) {
      debugPrint('Erro ao salvar mensagem localmente: $e');
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

  Future<Map<String, dynamic>> initiateChallenge(String username) async {
    return _sendAndWaitForResponse(
      {
        'action': 'initiate_challenge',
        'username': username,
      },
      'initiate_challenge_response',
    );
  }

  Future<Map<String, dynamic>> verifyChallenge(
      String username, String signature) async {
    return _sendAndWaitForResponse(
      {
        'action': 'verify_challenge',
        'username': username,
        'signature': signature,
      },
      'verify_challenge_response',
    );
  }

  //! digitação
  void sendTypingStart(String receiverUsername) {
    if (!_isAuthenticated()) return;

    final typingMessage = {
      'action': 'typing_start',
      'receiver_username': receiverUsername,
    };

    _sendMessageNow(typingMessage);
  }

  void sendTypingStop(String receiverUsername) {
    if (!_isAuthenticated()) return;

    final typingMessage = {
      'action': 'typing_stop',
      'receiver_username': receiverUsername,
    };

    _sendMessageNow(typingMessage);
  }

  //?auxiliares - ok até onde eu sei
  bool _isAuthenticated() {
    if (_userId == null) {
      debugPrint('⚠️ Ação requer autenticação. Faça login primeiro.');
      return false;
    }
    return true;
  }

  void _sendMessageNow(Map<String, dynamic> message) async {
    // Adicione async
    if (_socket == null || !_isConnected) {
      debugPrint('Socket não disponível para envio');
      return;
    }

    try {
      final Map<String, dynamic> messageToSend;

      if (_isEncryptionEnabled && message['action'] != 'handshake_init') {
        final encrypted = await _crypto.encryptMessage(json.encode(message));
        messageToSend = {
          'action': 'encrypted_message',
          ...encrypted,
        };
      } else {
        messageToSend = message;
      }

      final jsonMessage = json.encode(messageToSend);
      _socket!.add(utf8.encode('$jsonMessage\n'));
    } catch (e) {
      debugPrint('Erro ao enviar mensagem: $e');
      _messageController.add({
        'action': 'error',
        'message': 'Erro ao enviar mensagem: $e',
        'success': false
      });
    }
  }

  //gettrs
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;
  bool get isEncryptionEnabled => _isEncryptionEnabled;

  void disconnect() {
    _socket?.close();
    _isConnected = false;
    disableEncryption();
    _crypto.clearSessionKeys();
    _messageController.close();
    debugPrint('🔌 Desconectado do servidor');
  }
}
