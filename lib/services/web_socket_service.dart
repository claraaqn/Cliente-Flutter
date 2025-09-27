import 'dart:async' show StreamController;
import 'dart:convert';
import 'dart:developer' as console;
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  static const String serverUrl = 'ws://localhost:8080';

  bool _isConnected = false;
  String? _userId;
  String? _username;

  Future<bool> connect() async {
    if (_isConnected) return true;

    try {
      console.log('🔗 Conectando ao WebSocket em $serverUrl...');

      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _isConnected = true;

      _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (error) => _handleError(error),
        onDone: () => _handleDisconnect(),
      );

      console.log('✅ Conectado ao WebSocket em $serverUrl');
      return true;
    } catch (e) {
      console.log('❌ Erro ao conectar via WebSocket: $e');
      _isConnected = false;
      return false;
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = json.decode(data);
      console.log('📥 Mensagem recebida: $message');

      // Trata diferentes tipos de notificações em tempo real
      _handleRealTimeNotifications(message);

      _messageController.add(message);
    } catch (e) {
      console.log('❌ Erro ao decodificar mensagem: $e, dados: $data');
    }
  }

  void _handleRealTimeNotifications(Map<String, dynamic> message) {
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
    console.log('❌ Erro na conexão WebSocket: $error');
    _isConnected = false;
    _messageController.add({
      'action': 'error',
      'message': 'Erro de conexão WebSocket: $error',
      'success': false
    });
  }

  void _handleDisconnect() {
    console.log('🔌 Conexão WebSocket fechada');
    _isConnected = false;
    _userId = null;
    _username = null;
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

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _sendAndWaitForResponse(
      {
        'action': 'login',
        'username': username,
        'password': password,
      },
      'login_response',
    );

    if (response['success'] == true) {
      _userId = response['data']?['user_id']?.toString();
      _username = username;
      console.log('👤 Usuário logado: $_username (ID: $_userId)');
    }

    return response;
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

  Future<Map<String, dynamic>> sendFriendRequest(String friendUsername) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

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
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    return _sendAndWaitForResponse(
      {
        'action': 'respond_friend_request',
        'request_id': requestId,
        'response': responseType, // 'accepted' or 'rejected'
      },
      'respond_friend_request_response',
    );
  }

  Future<Map<String, dynamic>> getFriendRequests() async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

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

  // ============ MÉTODOS DE MENSAGENS ============
  Future<Map<String, dynamic>> sendMessage(
      String receiverUsername, String content) async {
    if (!_isAuthenticated()) {
      return {'success': false, 'message': 'Usuário não autenticado'};
    }

    return _sendAndWaitForResponse(
      {
        'action': 'send_message',
        'receiver_username': receiverUsername,
        'content': content,
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

  bool _isAuthenticated() {
    if (_userId == null) {
      console.log('⚠️ Ação requer autenticação. Faça login primeiro.');
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _sendAndWaitForResponse(
    Map<String, dynamic> message,
    String expectedResponseType,
  ) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) {
        return {
          'success': false,
          'message': 'Não foi possível conectar ao servidor',
        };
      }
    }

    try {
      final jsonMessage = json.encode(message);
      console.log('📤 Enviando mensagem: $jsonMessage');

      _channel!.sink.add(jsonMessage);

      final response = await _messageController.stream
          .firstWhere(
            (data) =>
                data['action'] == expectedResponseType ||
                data['success'] != null,
            orElse: () => {
              'success': false,
              'message': 'Timeout na resposta do servidor',
            },
          )
          .timeout(const Duration(seconds: 10));

      console.log('📥 Resposta recebida: $response');
      return response;
    } catch (e) {
      console.log('❌ Erro ao enviar mensagem: $e');
      return {'success': false, 'message': 'Erro: $e'};
    }
  }

  void _sendMessageNow(Map<String, dynamic> message) {
    try {
      if (_channel == null || !_isConnected) {
        console.log('❌ WebSocket não disponível para envio');
        return;
      }

      final jsonMessage = json.encode(message);
      console.log('📤 Enviando mensagem (sem resposta): $jsonMessage');
      _channel!.sink.add(jsonMessage);
    } catch (e) {
      console.log('❌ Erro ao enviar mensagem: $e');
    }
  }

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;
  String? get userId => _userId;
  String? get username => _username;

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _userId = null;
    _username = null;
    _messageController.close();
    console.log('🔌 WebSocketService desconectado');
  }
}
