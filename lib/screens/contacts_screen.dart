import 'dart:convert';
import 'package:cliente/screens/chat_screen.dart';
import 'package:cliente/services/crypto_service.dart';
import 'package:cliente/services/local_storage_service.dart';
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

  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadFriends();
    _loadPendingRequests();
  }

  void _resetAuthState() {
    setState(() {
      _isAuthenticating = false;
      _sentNonce = null; // Limpa o nonce antigo
    });
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
      } else if (action == "friend_request_accepted") {
        _handleFriendRequestAccepted(message);
      } else if (action == "handshake_finalizado") {
        // Passo 1: O Handshake de chaves acabou, A começa a autenticação
        _startMutualAuth(message);
      } else if (action == "auth_challenge") {
        // Passo 2: B recebe o desafio de A
        _handleAuthChallenge(message);
      } else if (action == "auth_response_and_challenge") {
        // Passo 3: A recebe a assinatura de B e o desafio de B
        _handleAuthResponseAndChallenge(message);
      } else if (action == "auth_final_verification") {
        // Passo 4: B verifica a assinatura de A
        _handleFinalVerification(message);
      } else if (action == "auth_complete") {
        debugPrint("AUTENTICAÇÃO MÚTUA CONCLUÍDA COM SUCESSO!");
        // Habilitar chat UI aqui
      } else if (action == "chaves_para_b") {
        _saveKeys(message);
      }
    });
  }

  Future<void> _saveKeys(Map<String, dynamic> data) async {
    // Use a instância que já existe no seu serviço de preferência
    final idFriendship = data["id_friendship"];
    final encry = data["encryption_key"];
    final hmac = data["hmac_key"];

    final cryptoService = CryptoService();
    final localstorage = LocalStorageService();

    if (idFriendship != null && encry != null && hmac != null) {
      debugPrint(
          '💾 Salvando as chaves recebidas do servidor para amizade: $idFriendship');

      // Certifique-se de que o idFriendship seja tratado como int
      final int id = int.parse(idFriendship.toString());

      await localstorage.saveFriendSessionKeys(id, encry, hmac);

      // ✅ Importante: Notificar o CryptoService que as chaves chegaram!
      cryptoService.setSessionKeysFriends(
        encryptionKey: base64Decode(encry),
        hmacKey: base64Decode(hmac),
      );
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
    final userId = authProvider.userId;

    debugPrint("ID de quem tá enviando o pedido de amizade $userId");

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

  Future<void> _acceptFriendRequest(int senderId, String pubkey) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final userId = authProvider.userId;

    debugPrint("Id de quem enviou o pedido de amizade $senderId");
    debugPrint("Id de quem recebeu o pedido de amizade $userId");

    try {
      final response =
          await socketService.respondFriendRequest('accepted', userId);

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

  // Variável para guardar o nonce que enviamos para validar a resposta depois
  String? _sentNonce;

  // Passo 1: A inicia
  Future<void> _startMutualAuth(Map<String, dynamic> data) async {
    if (_isAuthenticating) {
      debugPrint("⛔ Autenticação já em andamento (Start). Ignorando.");
      return;
    }
    _isAuthenticating = true;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();
    final localstorage = LocalStorageService();

    final userId = authProvider.userId;

    // cirando as chaves para assinatira:
    final keys = await cryptoService.generateKeyPair();
    final pubKey = keys["publicKey"];
    final privKey = keys["privateKey"];

    localstorage.saveMyPrivateKey(userId!, privKey!);
    localstorage.saveMyPublicteKey(userId, pubKey!);

    debugPrint("Iniciando Autenticação Mútua...");

    var receiverId = data['reciverId'];
    if (receiverId == null && data['data'] != null) {
      receiverId = data['data']['reciverId'];
    }

    debugPrint("Reciver id: $receiverId");

    if (receiverId == null) {
      debugPrint(
          "ERRO CRÍTICO: receiverId (Target ID) é nulo! Payload recebido: $data");
      return;
    }

    // 1. Gerar Nonce (ex: 4559)
    final nonce = cryptoService
        .generateSalt(); // Reutilizando sua funçao de salt para gerar string aleatoria
    _sentNonce = nonce; // Guardar para verificar depois

    // 2. Enviar desafio para o Servidor repassar ao Amigo
    // Nota: Idealmente, esse payload já deveria ser criptografado com a chave de sessão (AES)
    // Mas para seguir a lógica do desafio, mandaremos claro para ele assinar.

    final payload = {
      "action": "auth_challenge",
      "target_id": receiverId,
      "nonce": nonce,
      "senderPubKey": pubKey,
    };

    // Envie via socket
    socketService.sendMessageFriend(payload);
  }

  // Passo 2: B recebe o desafio, assina e manda o seu desafio
  Future<void> _handleAuthChallenge(Map<String, dynamic> message) async {
    if (_isAuthenticating) {
      debugPrint("⛔ Já estou processando uma autenticação.");
      return;
    }
    _isAuthenticating = true;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();
    final localstorage = LocalStorageService();
    debugPrint("Recebi desafio de autenticação");

    final senderId = message['sender_id']; // Quem mandou (A)
    final nonceReceived = message['nonce']; // O número (4559)
    final userId = authProvider.userId;

    debugPrint("Sender id: $senderId");
    debugPrint("Reciver id: $userId");

    final senderPubKey = message['senderPubKey'];
    if (senderPubKey != null) {
      debugPrint("Salvando chave pública temporária de A");
      await localstorage.saveFriendPublicKey(senderId, senderPubKey);
    } else {
      debugPrint(
          "AVISO: Cliente A não enviou chave pública. A validação final falhará.");
    }

    final keys = await cryptoService.generateKeyPair();
    final pubKey = keys["publicKey"];
    final privKey = keys["privateKey"];

    localstorage.saveMyPrivateKey(userId!, privKey!);
    localstorage.saveMyPublicteKey(userId, pubKey!);

    // 2. Assinar o nonce recebido
    final signature =
        await cryptoService.signData(utf8.encode(nonceReceived), privKey);

    // 3. Gerar meu próprio desafio (NonceB)
    final myNonce = cryptoService.generateSalt();
    _sentNonce = myNonce; // Guardo o que eu gerei

    final payload = {
      "action": "auth_response_and_challenge",
      "target_id": senderId,
      "original_nonce": nonceReceived,
      "signature": signature, // Prova que sou B
      "new_nonce": myNonce, // Desafio para A provar quem é
      "reciverId": userId,
      "reciverPubKey": pubKey,
    };

    socketService.sendMessageFriend(payload);
  }

  // Passo 3: A verifica a assinatura de B e assina o desafio de B
  Future<void> _handleAuthResponseAndChallenge(
      Map<String, dynamic> message) async {
    debugPrint("Verificando resposta do desafio...");
    final localstorage = LocalStorageService();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();

    final senderId = authProvider.userId;
    final originalNonce = message['original_nonce'];
    final signatureB = message['signature'];
    final nonceFromB = message['new_nonce'];
    final reciverId = message["reciverId"];

    debugPrint("Sender id: $senderId");
    debugPrint("Reciver id: $reciverId");

    // 1. Verificação de Segurança: O nonce que voltou é o mesmo que enviei?
    if (originalNonce != _sentNonce) {
      debugPrint(
          "ALERTA: Nonce incorreto! Esperado: $_sentNonce, Recebido: $originalNonce");
      _resetAuthState(); // Libera trava pois falhou
      return;
    }

    if (reciverId == Null) {
      debugPrint("O ID DO REVICER NÃO TÁ INDO");
    }

    // 2. Buscar chave pública de IDENTIDADE do amigo
    final reciverPubKey = message["reciverPubKey"];
    localstorage.saveFriendPublicKey(reciverId, reciverPubKey);

    // 3. Verificar assinatura
    final isValid = await cryptoService.verifySignature(
        data: utf8.encode(originalNonce),
        signatureB64: signatureB,
        publicKeyB64: reciverPubKey!);

    if (!isValid) {
      debugPrint("ERRO: Assinatura do amigo inválida!");
      return;
    }

    debugPrint(
        "Amigo autenticado com sucesso! Agora provando minha identidade...");

    // 4. Assinar o desafio de B (NonceB)
    final myPrivKey = await localstorage.getMyPrivateKey(senderId!);
    if (myPrivKey == null) {
      debugPrint("ERRO: Minha chave privada não encontrada!");
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

    // Para A, o processo acabou (ele validou B).
    // Pode chamar uma função para liberar o chat na UI.
    _onAuthSuccess();
  }

  // Passo 4: B verifica a assinatura de A
  Future<void> _handleFinalVerification(Map<String, dynamic> message) async {
    final localstorage = LocalStorageService();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;
    final cryptoService = CryptoService();

    final senderId = message['sender_id'];
    final originalNonce = message['original_nonce'];
    final signatureA = message['signature'];

    if (originalNonce != _sentNonce) {
      debugPrint("ALERTA: Nonce incorreto.");
      return;
    }

    final friendPubKey = await localstorage.getFriendPublicKey(senderId);

    if (friendPubKey == null) {
      debugPrint("ERRO: Não tenho a chave pública do amigo $senderId salva.");
      return;
    }

    final isValid = await cryptoService.verifySignature(
        data: utf8.encode(originalNonce),
        signatureB64: signatureA,
        publicKeyB64: friendPubKey);

    if (isValid) {
      debugPrint("Mútua autenticação completa! Chat Seguro.");
      // Avisa o outro lado (opcional, mas bom para UI)
      socketService.sendMessageFriend(
          {"action": "auth_complete", "target_id": senderId});
      _onAuthSuccess();
    } else {
      debugPrint("Falha ao autenticar o iniciador da conversa.");
    }
  }

  void _onAuthSuccess() {
    // Atualiza estado do Provider para liberar envio de mensagens
    // Provider.of<ChatProvider>(context, listen:false).setAuthenticated(true);
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

  Future<void> _handleFriendRequestAccepted(
      Map<String, dynamic> message) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    final senderId = message["sender_id"];
    final receiverPub = message["receiver_public_key"];
    final receiverId = message["receiver_id"];
    final idFriendship = message["id_friendship"];

    debugPrint("Id do sender $senderId");
    debugPrint("Chave do reciver $receiverPub");
    debugPrint("Id do request $receiverId");

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
                            onPressed: () => _acceptFriendRequest(
                                request['sender_id'],
                                request['sender_public_key']),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () =>
                                _rejectFriendRequest(request['receiver_id']),
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
    _friendUsernameController.dispose();
    super.dispose();
  }
}
