import 'dart:developer' as console;

import 'package:cliente/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cliente/providers/auth_provider.dart';
import 'package:cliente/models/friend.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Friend> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = true;
  String _errorMessage = '';
  final TextEditingController _friendUsernameController =
      TextEditingController();
  int _pendingRequestsCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadFriends();
    _loadPendingRequests();
  }

  void _initializeServices() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    // Escuta por mensagens do servidor
    socketService.messageStream.listen((message) {
      final action = message['action'];

      if (action == 'friend_request') {
        _showFriendRequestNotification(message);
        _loadPendingRequests();
      } else if (action == 'send_friend_request_response') {
        _handleFriendRequestResponse(message);
      } else if (action == 'get_friend_requests_response') {
        _handlePendingRequestsResponse(message);
      } else if (action == 'respond_friend_request_response') {
        _handleRespondFriendRequestResponse(message);
      } else if (action == 'get_friends_list_response') {
        _handleFriendsListResponse(message);
      }
    });
  }

  //! ajietar o front dessa função
  Future<void> _loadPendingRequests() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      final response = await socketService.getFriendRequests();

      if (response['success'] == true) {
        setState(() {
          _pendingRequests =
              List<Map<String, dynamic>>.from(response['data'] ?? []);
          _pendingRequestsCount = _pendingRequests.length;
        });
      } else {
        console.log('❌ Erro ao carregar solicitações: ${response['message']}');
      }
    } catch (e) {
      console.log('❌ Erro ao carregar solicitações pendentes: $e');
    }
  }

  Future<void> _loadFriends() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await socketService.getFriendsList();

      if (response['success'] == true) {
        final friendsList = (response['data'] as List?)
                ?.map((friendJson) => Friend.fromJson(friendJson))
                .toList() ??
            [];

        setState(() {
          _friends = friendsList;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Erro desconhecido';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao carregar amigos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _addFriend(String username) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await socketService.sendFriendRequest(username);

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Solicitação enviada')),
        );
        _loadFriends();
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Erro desconhecido';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao adicionar amigo: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _friendUsernameController.clear();
      });
    }
  }

  Future<void> _acceptFriendRequest(int? requestId) async {
    if (requestId == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      final response =
          await socketService.respondFriendRequest(requestId, 'accepted');

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Solicitação aceita')),
        );
        _loadPendingRequests();
        _loadFriends();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Erro ao aceitar')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao aceitar solicitação: $e')),
      );
    }
  }

  Future<void> _rejectFriendRequest(int? requestId) async {
    if (requestId == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      final response =
          await socketService.respondFriendRequest(requestId, 'rejected');

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(response['message'] ?? 'Solicitação rejeitada')),
        );
        _loadPendingRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Erro ao rejeitar')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao rejeitar solicitação: $e')),
      );
    }
  }

  void _handleFriendRequestResponse(Map<String, dynamic> response) {
    if (response['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Solicitação enviada')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(response['message'] ?? 'Erro ao enviar solicitação')),
      );
    }
  }

  void _handlePendingRequestsResponse(Map<String, dynamic> response) {
    if (response['success'] == true) {
      setState(() {
        _pendingRequests =
            List<Map<String, dynamic>>.from(response['data'] ?? []);
        _pendingRequestsCount = _pendingRequests.length;
      });
    }
  }

  void _handleRespondFriendRequestResponse(Map<String, dynamic> response) {
    if (response['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Ação realizada')),
      );
      _loadPendingRequests();
      _loadFriends();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Erro ao processar')),
      );
    }
  }

  void _handleFriendsListResponse(Map<String, dynamic> response) {
    if (response['success'] == true) {
      final friendsList = (response['data'] as List?)
              ?.map((friendJson) => Friend.fromJson(friendJson))
              .toList() ??
          [];

      setState(() {
        _friends = friendsList;
        _isLoading = false;
      });
    }
  }

  void _showFriendRequestNotification(Map<String, dynamic> message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova Solicitação de Amizade'),
        content: Text(message['message'] ?? 'Nova solicitação recebida'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ver Mais Tarde'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPendingRequestsDialog();
            },
            child: const Text('Ver Solicitações'),
          ),
        ],
      ),
    );
  }

  void _showPendingRequestsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitações de Amizade Pendentes'),
        content: _pendingRequests.isEmpty
            ? const Text('Nenhuma solicitação pendente')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _pendingRequests.length,
                  itemBuilder: (context, index) {
                    final request = _pendingRequests[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                            request['sender_username']?[0]?.toUpperCase() ??
                                '?'),
                      ),
                      title: Text(
                          request['sender_username'] ?? 'Usuário desconhecido'),
                      subtitle: Text(request['created_at']?.toString() ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () =>
                                _acceptFriendRequest(request['id']),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () =>
                                _rejectFriendRequest(request['id']),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showAddFriendBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Adicionar Amigo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _friendUsernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome de usuário',
                    border: OutlineInputBorder(),
                    hintText: 'Digite o username do amigo',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                      ),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final username = _friendUsernameController.text.trim();
                        if (username.isNotEmpty) {
                          _addFriend(username);
                          Navigator.pop(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Digite um username')),
                          );
                        }
                      },
                      child: const Text('Adicionar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatos'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: _showPendingRequestsDialog,
                tooltip: 'Solicitações pendentes',
              ),
              if (_pendingRequestsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _pendingRequestsCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadFriends();
              _loadPendingRequests();
            },
            tooltip: 'Recarregar',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authProvider.logout();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFriendBottomSheet,
        child: const Icon(Icons.person_add),
        tooltip: 'Adicionar amigo',
      ),
    );
  }

  Widget _buildContent() {
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _loadFriends();
                  _loadPendingRequests();
                },
                child: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_friends.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 20),
          const Text(
            'Nenhum amigo ainda',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Toque no botão + abaixo para adicionar amigos e começar a conversar',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _showAddFriendBottomSheet,
            child: const Text('Adicionar Primeiro Amigo'),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Meus Amigos (${_friends.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadFriends();
              await _loadPendingRequests();
            },
            child: ListView.builder(
              itemCount: _friends.length,
              itemBuilder: (context, index) {
                final friend = _friends[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        friend.username[0].toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    title: Text(
                      friend.username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      friend.isOnline
                          ? 'Online'
                          : friend.lastSeen != null
                              ? 'Offline'
                              : 'Offline',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.chat, color: Colors.blue),
                      onPressed: () {
                        // Navega para a tela de chat
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              friend: friend,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _friendUsernameController.dispose();
    super.dispose();
  }
}
