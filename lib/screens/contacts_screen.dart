import 'dart:convert';
import 'package:cliente/screens/chat_screen.dart';
import 'package:cliente/services/crypto_service.dart';
import 'package:cliente/services/friend_session_manager.dart';
import 'package:cliente/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cliente/providers/auth_provider.dart';
import 'package:cliente/models/friend.dart';
import 'dart:async';

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

  bool _isAuthenticating = false;

  final _localstorage = LocalStorageService();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadFriends();
    _loadPendingRequests();

    // _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    //   if (mounted) {
    //     _loadFriends();
    //   }
    // });
  }

  void _resetAuthState() {
    setState(() {
      _isAuthenticating = false;
      _sentNonce = null;
    });
  }

  void _initializeServices() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    socketService.messageStream.listen((message) async {
      final action = message['action'];

      if (action == 'friend_request') {
        _showFriendRequestNotification(message);
      } else if (action == 'send_friend_request_response') {
        _handleFriendRequestResponse(message);
      } else if (action == 'pedding_request') {
        _loadPendingRequests();
      } else if (action == 'get_friend_requests_response') {
        _handlePendingRequestsResponse(message);
      } else if (action == 'respond_friend_request_response') {
        _handleRespondFriendRequestResponse(message);
      } else if (action == 'get_friends_list_response') {
        _handleFriendsListResponse(message);
      } else if (action == "friend_request_accepted") {
        _handleFriendRequestAccepted(message);
      } else if (action == "handshake_finalizado") {
        _startMutualAuth(message);
      } else if (action == "auth_challenge") {
        _handleAuthChallenge(message);
      } else if (action == "auth_response_and_challenge") {
        _handleAuthResponseAndChallenge(message);
      } else if (action == "auth_final_verification") {
        _handleFinalVerification(message);
      } else if (action == "auth_complete") {
        debugPrint("AUTENTICAÇÃO MÚTUA CONCLUÍDA COM SUCESSO!");
        _onAuthSuccess();
      } else if (action == "chaves_para_b") {
        _saveKeys(message);
      } else if (action == "force_logout") {
        await _localstorage.clearUserCredentials();
        socketService.disconnect();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (Route<dynamic> route) => false,
          );
        });
      }
    });
  }

  Future<void> _saveKeys(Map<String, dynamic> data) async {
    final idFriendship = data["id_friendship"];
    final encry = data["encryption_key"];
    final hmac = data["hmac_key"];
    final cryptoService = CryptoService();

    if (idFriendship != null && encry != null && hmac != null) {
      await _localstorage.saveFriendSessionKeys(idFriendship, encry, hmac);
      cryptoService.setSessionKeysFriends(
        friendshipId: idFriendship,
        encryptionKey: base64Decode(encry),
        hmacKey: base64Decode(hmac),
      );

      if (idFriendship != null) {
        int fId = int.parse(idFriendship.toString());
        FriendSessionManager().resetSession(fId);
      }
    }
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
        debugPrint('Erro ao carregar solicitações: ${response['message']}');
      }
    } catch (e) {
      debugPrint('Erro ao carregar solicitações pendentes: $e');
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
        debugPrint("inferno");
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
    final userId = authProvider.userId;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await socketService.sendFriendRequest(username, userId);

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
    } finally {
      setState(() {
        _isLoading = false;
        _friendUsernameController.clear();
      });
    }
  }

  Future<void> _acceptFriendRequest(int senderId, String pubkey) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final userId = authProvider.userId;

    try {
      final response =
          await socketService.respondFriendRequest('accepted', userId);

      if (response['success'] == true) {
        setState(() {
          _pendingRequests.removeWhere((req) => req['sender_id']);
          _pendingRequestsCount = _pendingRequests.length;
        });
        _loadPendingRequests();
        _loadFriends();
      }
    } catch (e) {
      debugPrint("Erro: $e");
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
        setState(() {
          _pendingRequests
              .removeWhere((req) => req['receiver_id'] == requestId);
          _pendingRequestsCount = _pendingRequests.length;
        });
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

  String? _sentNonce;

  Future<void> _startMutualAuth(Map<String, dynamic> data) async {
    if (_isAuthenticating) {
      return;
    }
    _isAuthenticating = true;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();

    final userId = authProvider.userId;

    final keys = await cryptoService.generateKeyPair();
    final pubKey = keys["publicKey"];
    final privKey = keys["privateKey"];

    _localstorage.saveMyPrivateKey(userId!, privKey!);
    _localstorage.saveMyPublicteKey(userId, pubKey!);

    debugPrint("Iniciando Autenticação Mútua...");

    var receiverId = data['reciverId'];
    if (receiverId == null && data['data'] != null) {
      receiverId = data['data']['reciverId'];
    }

    debugPrint("Reciver id: $receiverId");

    if (receiverId == null) {
      return;
    }

    final nonce = cryptoService.generateSalt();
    _sentNonce = nonce;

    final payload = {
      "action": "auth_challenge",
      "target_id": receiverId,
      "nonce": nonce,
      "senderPubKey": pubKey,
    };

    socketService.sendMessageFriend(payload);
  }

  Future<void> _handleAuthChallenge(Map<String, dynamic> message) async {
    if (_isAuthenticating) {
      return;
    }
    _isAuthenticating = true;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();
    debugPrint("Recebi desafio de autenticação");

    final senderId = message['sender_id'];
    final nonceReceived = message['nonce'];
    final userId = authProvider.userId;

    final senderPubKey = message['senderPubKey'];
    if (senderPubKey != null) {
      await _localstorage.saveFriendPublicKey(senderId, senderPubKey);
    }

    final keys = await cryptoService.generateKeyPair();
    final pubKey = keys["publicKey"];
    final privKey = keys["privateKey"];

    _localstorage.saveMyPrivateKey(userId!, privKey!);
    _localstorage.saveMyPublicteKey(userId, pubKey!);

    final signature =
        await cryptoService.signData(utf8.encode(nonceReceived), privKey);

    final myNonce = cryptoService.generateSalt();
    _sentNonce = myNonce;

    final payload = {
      "action": "auth_response_and_challenge",
      "target_id": senderId,
      "original_nonce": nonceReceived,
      "signature": signature,
      "new_nonce": myNonce,
      "reciverId": userId,
      "reciverPubKey": pubKey,
    };

    socketService.sendMessageFriend(payload);
  }

  Future<void> _handleAuthResponseAndChallenge(
      Map<String, dynamic> message) async {
    debugPrint("Verificando resposta do desafio...");
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();

    final senderId = authProvider.userId;
    final originalNonce = message['original_nonce'];
    final signatureB = message['signature'];
    final nonceFromB = message['new_nonce'];
    final reciverId = message["reciverId"];

    if (originalNonce != _sentNonce) {
      debugPrint(
          "ALERTA: Nonce incorreto! Esperado: $_sentNonce, Recebido: $originalNonce");
      _resetAuthState();
      return;
    }

    if (reciverId == Null) {
      debugPrint("O ID DO REVICER NÃO TÁ INDO");
    }

    final reciverPubKey = message["reciverPubKey"];
    _localstorage.saveFriendPublicKey(reciverId, reciverPubKey);

    final isValid = await cryptoService.verifySignature(
        data: utf8.encode(originalNonce),
        signatureB64: signatureB,
        publicKeyB64: reciverPubKey!);

    if (!isValid) {
      return;
    }

    final myPrivKey = await _localstorage.getMyPrivateKey(senderId!);
    if (myPrivKey == null) {
      return;
    }

    final mySignature =
        await cryptoService.signData(utf8.encode(nonceFromB), myPrivKey);

    final payload = {
      "action": "auth_final_verification",
      "target_id": reciverId,
      "original_nonce": nonceFromB,
      "signature": mySignature,
    };

    socketService.sendMessageFriend(payload);

    _onAuthSuccess();
  }

  Future<void> _handleFinalVerification(Map<String, dynamic> message) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();

    final senderId = message['sender_id'];
    final originalNonce = message['original_nonce'];
    final signatureA = message['signature'];

    if (originalNonce != _sentNonce) {
      return;
    }

    final friendPubKey = await _localstorage.getFriendPublicKey(senderId);

    if (friendPubKey == null) {
      return;
    }

    final isValid = await cryptoService.verifySignature(
        data: utf8.encode(originalNonce),
        signatureB64: signatureA,
        publicKeyB64: friendPubKey);

    if (isValid) {
      debugPrint("Mútua autenticação completa! Chat Seguro.");
      socketService.sendMessageFriend(
          {"action": "auth_complete", "target_id": senderId});
      _onAuthSuccess();
    } else {
      debugPrint("Falha ao autenticar o iniciador da conversa.");
    }
  }

  void _onAuthSuccess() {
    debugPrint("Atualizando lista de contatos após autenticação segura.");
    _loadFriends();
    _isAuthenticating = false;
  }

  void _handleFriendRequestResponse(Map<String, dynamic> response) {
    if (response['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Solicitação enviada')),
      );
    } else {
      debugPrint("Erro");
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

  Future<void> _handleFriendRequestAccepted(
      Map<String, dynamic> message) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    final senderId = message["sender_id"];
    final receiverPub = message["receiver_public_key"];
    final receiverId = message["receiver_id"];
    final idFriendship = message["id_friendship"];

    final handshakeResponse = await socketService.handshakeFriends(
        senderId, receiverPub, receiverId, idFriendship);

    if (handshakeResponse['success'] == true) {
      debugPrint(
          "Handshake OK via await. Iniciando autenticação mútua direta...");
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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Solicitações Pendentes'),
              contentPadding: EdgeInsets.zero, 
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              content: _pendingRequests.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('Nenhuma solicitação pendente'),
                    )
                  : SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _pendingRequests.length,
                        itemBuilder: (context, index) {
                          final request = _pendingRequests[index];
                          String formattedDate = 'Data desconhecida';
                          try {
                            if (request['created_at'] != null) {
                              DateTime dt = DateTime.parse(request['created_at'].toString());
                              String hour = dt.hour.toString().padLeft(2, '0');
                              String minute = dt.minute.toString().padLeft(2, '0');
                              String day = dt.day.toString().padLeft(2, '0');
                              String month = dt.month.toString().padLeft(2, '0');
                              String year = dt.year.toString();
                              formattedDate = "$hour:$minute $day/$month/$year";
                            }
                          } catch (e) {
                            formattedDate = request['created_at'].toString();
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            leading: CircleAvatar(
                              radius: 18,
                              child: Text(request['sender_username']?[0]?.toUpperCase() ?? '?'),
                            ),
                            title: Text(
                              request['sender_username'] ?? 'Usuário',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              'Enviado em: $formattedDate',
                              style: const TextStyle(fontSize: 10), 
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                                  onPressed: () async {
                                    await _acceptFriendRequest(
                                        request['sender_id'],
                                        request['sender_public_key']);
                                    setDialogState(() {});
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                                  onPressed: () async {
                                    await _rejectFriendRequest(request['receiver_id']);
                                    setDialogState(() {});
                                  },
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
            );
          },
        );
      },
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
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (Route<dynamic> route) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFriendBottomSheet,
        tooltip: 'Adicionar amigo',
        child: const Icon(Icons.person_add),
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
    _refreshTimer?.cancel();
    _friendUsernameController.dispose();
    super.dispose();
  }
}
