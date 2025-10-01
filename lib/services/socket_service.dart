import 'dart:developer' as console;
import 'dart:io';
import 'dart:convert';
import 'dart:async';

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

  //? handles
  Future<bool> connect() async {
    if (_isConnected) return true;

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

      console.log('✅ Conectado ao servidor TCP em $serverHost:$serverPort');
      return true;
    } catch (e) {
      console.log('❌ Erro ao conectar via TCP: $e');
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
            console.log(
                '⚠️ Erro ao decodificar JSON: $e\nMensagem: $completeMessage');
          }
        }
      }

      // Mantém a última no buffer
      _messageBuffer
        ..clear()
        ..write(messages.last);
    } catch (e) {
      console.log('❌ Erro ao processar dados: $e');
    }
  }

  void handleRealTimeNotifications(Map<String, dynamic> message) {
    final action = message['action'];

    switch (action) {
      case 'friend_request':
        console.log('🎯 Nova solicitação de amizade: ${message['message']}');
        break;
      case 'new_message':
        console.log('📨 Nova mensagem recebida: ${message['content']}');
        break;
      case 'user_status_change':
        console.log(
            '🌐 Status alterado: ${message['username']} está ${message['is_online'] ? 'online' : 'offline'}');
        break;
      case 'user_typing':
        console.log('✍️ ${message['username']} está digitando...');
        break;
    }
  }

  void _handleError(dynamic error) {
    console.log('❌ Erro na conexão TCP: $error');
    _isConnected = false;
    _messageController.add({
      'action': 'error',
      'message': 'Erro de conexão TCP: $error',
      'success': false,
    });
  }

  void _handleDisconnect() {
    console.log('🔌 Conexão TCP fechada');
    _isConnected = false;
  }

  //? tudo aqui cunciona - autenticação
  Future<Map<String, dynamic>> login(String username, String password) async {
    final message = {
      'action': 'login',
      'username': username,
      'password': password,
    };
    final response = await _sendAndWaitForResponse(message, 'login_response');
    if (response['success'] == true) {
      _username = username;
      _userId = response['data']?['user_id'].toString();
      ;
    }
    return response;
  }

  Future<Map<String, dynamic>> registerUser(
      String username, String password) async {
    return _sendAndWaitForResponse(
      {
        'action': 'register',
        'username': username,
        'password': password,
      },
      'register_response',
    );
  }

  Future<Map<String, dynamic>> logout() async {
    final response = await _sendAndWaitForResponse(
      {
        'action': 'logout',
      },
      'logout_response',
    );

    if (response['success'] == true) {
      _userId = null;
      _username = null;
      console.log('👤 Usuário deslogado');
    }

    return response;
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
    if (receiverUsername.isEmpty) {
      return {'success': false, 'message': 'Destinatário inválido'};
    }
    if (content.isEmpty) {
      return {'success': false, 'message': 'Mensagem vazia'};
    }

    console.log('💬 Enviando mensagem para $receiverUsername: $content');

    return _sendAndWaitForResponse(
      {
        'action': 'send_message',
        'receiver_username': receiverUsername,
        'content': content,
        'sender_id': _userId,
        'sender_username': _username,
        'timestamp': DateTime.now().toIso8601String(),
      },
      'send_message_response',
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

  Future<Map<String, dynamic>> sendMessageToUser(
      String receiverUsername, String content) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }
    if (receiverUsername.isEmpty) {
      return {'success': false, 'message': 'Destinatário inválido'};
    }
    if (content.isEmpty) {
      return {'success': false, 'message': 'Mensagem vazia'};
    }

    console.log('💬 Enviando mensagem para $receiverUsername: $content');

    return _sendAndWaitForResponse(
      {
        'action': 'send_message',
        'receiver_username': receiverUsername,
        'content': content,
        'sender_id': _userId,
        'sender_username': _username,
        'timestamp': DateTime.now().toIso8601String(),
      },
      'send_message_response',
    );
  }

  Future<Map<String, dynamic>> getUndeliveredMessages() async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }
    return _sendAndWaitForResponse(
      {
        'action': 'get_undelivered_messages',
      },
      'get_undelivered_messages_response',
    );
  }

  Future<Map<String, dynamic>> getConversationHistory(String otherUserId,
      {int limit = 50}) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    return _sendAndWaitForResponse(
      {
        'action': 'get_conversation_history',
        'other_user_id': otherUserId,
        'limit': limit,
      },
      'get_conversation_history_response',
    );
  }

  Future<Map<String, dynamic>> getContacts() async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }
    return _sendAndWaitForResponse(
      {
        'action': 'get_contacts',
      },
      'get_contacts_response',
    );
  }

  void _processRealTimeMessage(Map<String, dynamic> message) {
    final action = message['action'];

    if (action == 'new_message') {
      console
          .log('🔔 Nova mensagem em tempo real via TCP: ${message['content']}');
    } else if (action == 'user_typing') {
      console.log(
          '✍️ Indicador de digitação via TCP: ${message['username']} está ${message['is_typing'] ? 'digitando' : 'parou'}');
    }
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
      console.log('⚠️ Ação requer autenticação. Faça login primeiro.');
      return false;
    }
    return true;
  }

  void _sendMessageNow(Map<String, dynamic> message) {
    if (_socket == null || !_isConnected) {
      console.log('⚠️ Socket não disponível para envio');
      return;
    }

    try {
      final jsonMessage = json.encode(message);
      console.log('📤 Enviando: $jsonMessage');
      _socket!.add(utf8.encode('$jsonMessage\n'));
    } catch (e) {
      console.log('❌ Erro ao enviar mensagem: $e');
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
    console.log('🔌 Desconectado do servidor');
  }
}
