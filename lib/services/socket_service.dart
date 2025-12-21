import 'dart:io';
import 'dart:convert';
import 'package:cliente/services/hand_shake_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:cliente/services/crypto_service.dart';
import 'package:cliente/services/messagecrypo_servece.dart';
import 'package:flutter/widgets.dart';
import 'package:cliente/services/local_storage_service.dart';
import 'package:cliente/services/friend_session_manager.dart';

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
  StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final _messageBuffer = StringBuffer();

  // Configurações do servidor
  static const String serverHost = '10.0.2.2'; // ip para emuladores
  static const int serverPort = 8081;

  // Timeout
  static const Duration defaultTimeout = Duration(seconds: 10);

  final LocalStorageService _localStorage = LocalStorageService();

  int? _authenticatedUserId;
  bool get isAuthenticated => _authenticatedUserId != null;

  HandshakeService? _handshakeService;
  final _friendSessionManager = FriendSessionManager();

  void setHandshakeService(HandshakeService service) {
    _handshakeService = service;
  }

  void setAuthenticatedUser({required int userId, required String username}) {
    _authenticatedUserId = userId;
    _userId = userId.toString(); // Sincroniza a String usada no sendMessage
    _username = username;
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
    if (_isConnected) return true;

    if (_messageController.isClosed) {
      _messageController = StreamController<Map<String, dynamic>>.broadcast();
    }
    if (_isConnecting) {
      debugPrint("!!Conexão já em andamento...");
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

  Future<Map<String, dynamic>> loginAsNewDevice({
    required String username,
    required String password,
    required String newPublicKey,
  }) async {
    return await _sendAndWaitForResponse({
      'action': 'login_new_device',
      'username': username,
      'password': password,
      'new_public_key': newPublicKey,
    }, 'login_new_device_response');
  }

  Future<Map<String, dynamic>> sendHandshakeInit({
    required String dhePublicKey,
    required String salt,
    required bool isRenegotiation,
  }) async {
    final response = {
      'action': 'handshake_init',
      'dhe_public_key': dhePublicKey,
      'salt': salt,
      'request_id': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    if (isRenegotiation && _isEncryptionEnabled) {
      final encryptedPacket =
          await _crypto.encryptMessage(json.encode(response));

      final wrapper = {
        'action': 'encrypted_message',
        ...encryptedPacket,
      };

      return _sendAndWaitForResponse(wrapper, 'handshake_response');
    } else {
      // 🔓 INICIAL: Envia em texto plano
      return _sendAndWaitForResponse(response, 'handshake_response');
    }
  }

  //? funciona - amizade
  Future<Map<String, dynamic>> sendFriendRequest(
      String friendUsername, int userId) async {
    final keys = await _crypto.generateDHEKeyPair();
    final pubA = keys["publicKey"];
    final priA = keys["privateKey"];

    _localStorage.saveMyPrivateKeyDHE(userId, priA!);
    _localStorage.saveMyPublicteKeyDHE(userId, pubA!);

    return _sendAndWaitForResponse(
      {
        'action': 'send_friend_request',
        'sender_id': userId,
        'receiver_username': friendUsername,
        "dhe_public_sender": pubA
      },
      'send_friend_request_response',
    );
  }

  Future<Map<String, dynamic>> respondFriendRequest(
      String responseType, int userId) async {
    final keys = await _crypto.generateDHEKeyPair();
    final pubB = keys["publicKey"];
    final privB = keys["privateKey"];

    _localStorage.saveMyPrivateKeyDHE(userId, privB!);
    _localStorage.saveMyPublicteKeyDHE(userId, pubB!);

    return _sendAndWaitForResponse(
      {
        'action': 'respond_friend_request',
        'reciverId': userId,
        'response': responseType,
        "dhe_public_reciver": pubB,
      },
      'respond_friend_request_response',
    );
  }

  Future<Map<String, dynamic>> handshakeFriends(
      int senderId, String receiverPub, int reciverId, int idFriendship) async {
    debugPrint('Começando HandShake');

    _localStorage.saveFriendPublicKey(reciverId, receiverPub);

    final privA = await _localStorage.getMyPrivateKeyDH(senderId);

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

    final encBase64 = base64Encode(sessionKeys['encryption']!);
    final hmacBase64 = base64Encode(sessionKeys['hmac']!);

    debugPrint('💾 Salvando as chaves para o id de amizade: $idFriendship');
    await _localStorage.saveFriendSessionKeys(
        idFriendship, encBase64, hmacBase64);

    final check = await _localStorage.getFriendSessionKeys(idFriendship);
    debugPrint(
        '🔍 Verificação pós-salvamento: ${check != null ? "Sucesso" : "Falha"}');

    _crypto.setSessionKeysFriends(
      friendshipId: idFriendship,
      encryptionKey: sessionKeys['encryption']!,
      hmacKey: sessionKeys['hmac']!,
    );

    debugPrint('Handshake realizado - Chaves de sessão geradas');
    _friendSessionManager.resetSession(idFriendship);

    return _sendAndWaitForResponse({
      "action": "handshake_complete",
      "id_friendship": idFriendship,
      "reciverId": reciverId,
      "session_id": sessionId,
      "salt": sessionSalt,
      "encryption_key": encBase64,
      "hmac_key": hmacBase64,
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
  Future<Map<String, dynamic>> sendMessage(String receiverUsername,
      String content, int idFriendship, int reciverId) async {
    if (_handshakeService != null) {
      if (_handshakeService!.sessionManager.shouldRenegotiate()) {
        debugPrint("Limite da sessão atingido. Renegociando chaves...");
        bool renewed =
            await _handshakeService!.initiateHandshake(isRenegotiation: true);
        if (!renewed) {
          return {
            'success': false,
            'message': 'Falha ao renovar chaves de sessão'
          };
        }
      }
    }
    // 1. Validações Básicas
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    if (receiverUsername.isEmpty || content.isEmpty) {
      return {'success': false, 'message': 'Dados inválidos'};
    }

    debugPrint('Enviando mensagem para $receiverUsername: $content');

    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}_$_userId';

    final messageData = {
      'sender_id': _userId,
      'sender_username': _username,
      'receiver_username': receiverUsername,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'local_id': localId,
      'id_friendship': idFriendship,
    };

    try {
      await _localStorage.saveMessageLocally(messageData);
      debugPrint('Mensagem salva localmente: $localId');
    } catch (e) {
      debugPrint('Erro ao salvar localmente (DB não iniciado?): $e');
    }

    try {
      if (_friendSessionManager.shouldRotate(idFriendship)) {
        try {
          String? receiverPub =
              await _localStorage.getFriendPublicKey(reciverId);
          if (receiverPub != null) {
            await handshakeFriends(
                _authenticatedUserId!, receiverPub, reciverId, idFriendship);
          }
        } catch (e) {
          debugPrint("Erro ao tentar renovar sessão: $e");
        }
      }

      Map<String, dynamic> plainMessage = {
        'action': 'send_message',
        'receiver_username': receiverUsername,
        'content': content,
        'sender_id': _userId,
        'sender_username': _username,
        'timestamp': DateTime.now().toIso8601String(),
        'local_id': localId,
        'id_friendship': idFriendship,
      };

      // 4. CAMADA 1: Criptografia de Amigo (Ponta-a-Ponta)
      bool friendReady = await ensureSessionReady(idFriendship);
      _friendSessionManager.incrementMessageCount(idFriendship);

      if (friendReady) {
        debugPrint("Criptografando conteúdo para o amigo...");
        try {
          final encryptedContentMap =
              await _crypto.encryptMessageFriend(content, idFriendship);

          plainMessage['content'] = json.encode(encryptedContentMap);
        } catch (e) {
          debugPrint("Erro ao cifrar conteúdo de amigo: $e");
        }
      } else {
        debugPrint(
            "Chaves de amigo não encontradas. Enviando conteúdo legível para o servidor.");
      }

      // 5. CAMADA 2: Criptografia de Servidor (Túnel)
      final Map<String, dynamic> messageToSend;

      if (_isEncryptionEnabled) {
        _handshakeService?.sessionManager.incrementMessageCount();

        final encryptedPacket =
            await _crypto.encryptMessage(json.encode(plainMessage));
        messageToSend = {
          'action': 'encrypted_message',
          ...encryptedPacket,
        };
      } else {
        // Fallback: Se não houver nem criptografia de servidor (raro)
        messageToSend = plainMessage;
      }

      // 6. Envio
      final response = await _sendAndWaitForResponse(
        messageToSend,
        'send_message_response',
      );

      // 7. Processa Resposta
      if (response['success'] == true) {
        final messageId = response['data']['message_id'];
        final isOffline = response['data']['is_offline'] == true;

        if (messageId != null) {
          try {
            await _localStorage.markMessageAsSent(localId, messageId);
          } catch (_) {}
        }

        debugPrint(isOffline
            ? 'Mensagem salva no servidor (destinatário offline)'
            : 'Mensagem entregue em tempo real');
      }

      return response;
    } catch (e) {
      debugPrint('Erro crítico no envio: $e');
      return {
        'success': false,
        'message': 'Erro no envio: $e',
        'local_id': localId,
      };
    }
  }

  Future<bool> ensureSessionReady(int idFriendship) async {
    // 1. Verifica se já está na RAM (Rápido)

    // 2. Tenta restaurar do LocalStorage (Cache)
    final keys = await _localStorage.getFriendSessionKeys(idFriendship);
    if (keys != null) {
      try {
        _crypto.setSessionKeysFriends(
          friendshipId: idFriendship,
          encryptionKey: base64Decode(keys['encryption']!),
          hmacKey: base64Decode(keys['hmac']!),
        );
        return true;
      } catch (e) {
        debugPrint("Erro ao decodificar chaves do cache: $e");
      }
    }

    debugPrint("❌ Nenhuma chave encontrada no cache. Handshake necessário.");
    return false;
  }

  Future<void> checkPendingMessages() async {
    if (!_isAuthenticated() || !_isConnected) return;

    try {
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
          final decryptedData = await _tryDecryptFriendLayer(message);

          final newMessage = {
            'action': 'new_message',
            'id': decryptedData['id'],
            'sender_id': decryptedData['sender_id'],
            'receiver_id': _authenticatedUserId,
            'content': decryptedData['content'],
            'timestamp': decryptedData['timestamp'],
            'is_delivered': true,
            'id_friendship': decryptedData['id_friendship'],
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

  void sendMessageFriend(Map<String, dynamic> message) {
    if (_socket != null) {
      debugPrint("Enviando ação: ${message['action']}");
      _socket!.write('${json.encode(message)}\n');
    } else {
      debugPrint(
          "Erro: Socket desconectado ao tentar enviar ${message['action']}");
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
      Map<String, dynamic> processedMessage = message;

      if (_isEncryptionEnabled && _isEncryptedMessage(message)) {
        processedMessage = await _decryptReceivedMessage(message);
      }

      if (processedMessage['action'] == 'new_message') {
        processedMessage = await _tryDecryptFriendLayer(processedMessage);
      }

      _messageController.add(processedMessage);
    } catch (e) {
      debugPrint('Erro ao processar mensagem: $e');
      _messageController.add({
        'action': 'error',
        'message': 'Erro ao processar: $e',
        'success': false,
      });
    }
  }

  Future<Map<String, dynamic>> _tryDecryptFriendLayer(
      Map<String, dynamic> message) async {
    final dynamic rawContent = message['content'];

    if (rawContent is! String || !rawContent.trim().startsWith('{'))
      return message;

    try {
      final Map<String, dynamic> contentMap = json.decode(rawContent);

      if (contentMap.containsKey('ciphertext') &&
          contentMap.containsKey('hmac')) {
        final idValue = message['id_friendship'] ?? message['id_friendship'];

        if (idValue == null) {
          return message;
        }

        final int idFriendship = int.parse(idValue.toString());

        bool ready = await ensureSessionReady(idFriendship);

        if (ready) {
          final Map<String, String> cryptoPayload = {
            'ciphertext': contentMap['ciphertext'].toString(),
            'hmac': contentMap['hmac'].toString(),
          };

          final String decryptedText =
              await _crypto.decryptMessageFriend(cryptoPayload, idFriendship);
          message['content'] = decryptedText;
        } else {
          message['content'] = "Mensagem criptografada (Chaves indisponíveis)";
        }
      }
    } catch (e) {
      debugPrint("Aviso: Falha ao processar camada: $e");
    }
    return message;
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
    debugPrint('Iniciando desconexão...');
    _isConnected = false;
    _socket?.destroy();
    _socket = null;
    disableEncryption();
    _crypto.clearSessionKeys();
    clearAuthentication();
    if (!_messageController.isClosed) {
      _messageController.add({'action': 'socket_disconnected'});
    }
  }
}
