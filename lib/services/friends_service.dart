import 'package:cliente/services/web_socket_service.dart';

class FriendService {
  final WebSocketService webSocketService;

  FriendService(this.webSocketService);

  Future<void> addFriend(String username) async {
    final response = await webSocketService.sendFriendRequest(username);

    if (response['success']) {
      print('✅ Pedido de amizade enviado para $username');
    } else {
      print('❌ Erro: ${response['message']}');
    }
  }

  Future<void> acceptFriendRequest(int requestId) async {
    final response =
        await webSocketService.respondFriendRequest(requestId, 'accepted');

    if (response['success']) {
      print('✅ Pedido de amizade aceito');
    } else {
      print('❌ Erro: ${response['message']}');
    }
  }

  Future<void> loadFriends() async {
    final response = await webSocketService.getFriendsList();

    if (response['success']) {
      final friends = response['data'];
      print('👥 Lista de amigos: $friends');
    } else {
      print('❌ Erro: ${response['message']}');
    }
  }
}