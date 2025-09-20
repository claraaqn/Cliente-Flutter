import 'dart:io';
import 'dart:convert';
import 'dart:async';

class SocketService {
  Socket? _socket;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  static const String serverHost =
      '10.0.2.2'; // ip para emular em outros dispositivos
  static const int serverPort = 8080;

  bool _isConnected = false;
  final _messageBuffer = StringBuffer();

  Future<bool> connect() async {
    if (_isConnected) return true;

    try {
      _socket = await Socket.connect(serverHost, serverPort,
          timeout: const Duration(seconds: 10));
      _isConnected = true;

      // Listen para dados do servidor
      _socket!.listen(
        (data) => _handleData(data),
        onError: (error) => _handleError(error),
        onDone: () => _handleDisconnect(),
        cancelOnError: true,
      );

      print('Conectado ao servidor TCP em $serverHost:$serverPort');
      return true;
    } catch (e) {
      print('Erro ao conectar via TCP: $e');
      _isConnected = false;
      return false;
    }
  }

  void _handleData(List<int> data) {
    try {
      final message = utf8.decode(data);
      _messageBuffer.write(message);

      // Tenta processar mensagens completas (separadas por \n)
      final bufferContent = _messageBuffer.toString();
      final messages = bufferContent.split('\n');

      if (messages.length > 1) {
        // Processa todas as mensagens completas exceto a última (que pode estar incompleta)
        for (int i = 0; i < messages.length - 1; i++) {
          final completeMessage = messages[i].trim();
          if (completeMessage.isNotEmpty) {
            try {
              final jsonData = json.decode(completeMessage);
              _messageController.add(jsonData);
            } catch (e) {
              print('Erro ao decodificar JSON: $e, mensagem: $completeMessage');
            }
          }
        }

        // Mantém a última mensagem (possivelmente incompleta) no buffer
        _messageBuffer.clear();
        _messageBuffer.write(messages.last);
      }
    } catch (e) {
      print('Erro ao processar dados: $e');
    }
  }

  void _handleError(dynamic error) {
    print('Erro na conexão TCP: $error');
    _isConnected = false;
    _messageController.add({
      'type': 'error',
      'message': 'Erro de conexão TCP: $error',
    });
  }

  void _handleDisconnect() {
    print('Conexão TCP fechada');
    _isConnected = false;
  }

  Future<Map<String, dynamic>> registerUser(
      String username, String password) async {
    return _sendAndWaitForResponse(
      {
        'type': 'register',
        'username': username,
        'password': password,
      },
      'register_response',
    );
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    return _sendAndWaitForResponse(
      {
        'type': 'login',
        'username': username,
        'password': password,
      },
      'login_response',
    );
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
          'message': 'Não foi possível conectar ao servidor TCP',
        };
      }
    }

    try {
      // Envia a mensagem com quebra de linha para delimitar
      final jsonMessage = json.encode(message) + '\n';
      _socket!.write(jsonMessage);

      final response = await _messageController.stream
          .firstWhere(
            (data) => data['type'] == expectedResponseType,
            orElse: () => {
              'type': 'timeout',
              'success': false,
              'message': 'Timeout na resposta do servidor',
            },
          )
          .timeout(const Duration(seconds: 10));

      return response;
    } catch (e) {
      return {'success': false, 'message': 'Erro: $e'};
    }
  }

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;

  void disconnect() {
    _socket?.close();
    _isConnected = false;
    _messageController.close();
  }
}
