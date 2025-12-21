import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cliente/models/friend.dart';
import 'package:cliente/models/message.dart';
import 'package:cliente/providers/auth_provider.dart';
import 'package:cliente/services/local_storage_service.dart';

class ChatScreen extends StatefulWidget {
  final Friend friend;

  const ChatScreen({super.key, required this.friend});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;
  bool _isTyping = false;
  bool _isCurrentlyTyping = false;
  bool _friendOnline = false;
  bool _hasLoadedLocalMessages = false;

  Timer? _typingDebounceTimer;
  static const int _typingDebounceMs = 1000;
  Timer? _typingTimer;

  StreamSubscription? _messageSubscription;
  LocalStorageService? _localStorage;

  @override
  void initState() {
    super.initState();
    debugPrint('ChatScreen iniciado para: ${widget.friend.username}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _localStorage ??= Provider.of<LocalStorageService>(context, listen: false);
  }

  Future<void> _initializeData() async {
    _localStorage = Provider.of<LocalStorageService>(context, listen: false);
    _initializeChat();
    await _loadLocalMessages();
    if (mounted && _isLoading) {
      setState(() {
        _isLoading = false;
      });
    }
    _syncUnsentMessages();
    _checkPendingMessages();
  }

  void _initializeChat() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    _messageSubscription = socketService.messageStream.listen((message) {
      if (!mounted) return;

      final action = message['action'];

      if (action == 'new_message') {
        _handleNewMessage(message);
      } else if (action == 'user_typing') {
        _handleTypingIndicator(message);
      } else if (action == 'user_online_status') {
        _handleOnlineStatus(message);
      }
    });
  }

//! mensagens

  void _handleNewMessage(Map<String, dynamic> message) {
    try {
      final content = message['content'];
      if (content is String &&
          content.contains('ciphertext') &&
          content.contains('hmac')) {
        return;
      }

      final currentUserId =
          Provider.of<AuthProvider>(context, listen: false).userId;
      final newMessage = _createMessageFromMap(message, currentUserId);

      if (newMessage != null) {
        final isDuplicate = _messages.any((msg) {
          if (msg.id != null && newMessage.id != null) {
            return msg.id == newMessage.id;
          }
          final timeDiff =
              msg.timestamp.difference(newMessage.timestamp).inSeconds.abs();

          return msg.content == newMessage.content &&
              msg.senderId == newMessage.senderId &&
              timeDiff < 2;
        });

        if (!isDuplicate) {
          if (mounted) {
            setState(() {
              _messages.add(newMessage);
              _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            });

            Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);

            _saveMessageLocally(newMessage);
          }
        } else {
          debugPrint('Mensagem duplicada ignorada (UI já atualizada)');
        }
      }
    } catch (e) {
      debugPrint('Erro ao processar nova mensagem: $e');
    }
  }

  Future<void> _saveMessageLocally(Message message) async {
    if (_localStorage == null) return;

    try {
      final messageData = {
        'id': message.id, 
        'sender_id': message.senderId,
        'sender_username': message.isMine ? 'Eu' : widget.friend.username,
        'receiver_username': message.isMine ? widget.friend.username : 'Eu',
        'content': message.content,
        'timestamp': message.timestamp.toIso8601String(),
        'is_delivered': message.isDelivered,
        'is_read': 0,
      };

      if (message.isMine) {
        await _localStorage!.saveMessageLocally(messageData);
      } else {
        await _localStorage!.saveReceivedMessage(messageData);
      }
    } catch (e) {
      debugPrint('Erro ao salvar mensagem no LocalStorage: $e');
    }
  }

  void _handleTypingIndicator(Map<String, dynamic> message) {
    final username = message['username'];
    final isTyping = message['is_typing'] == true;

    if (username == widget.friend.username) {
      if (mounted) {
        setState(() {
          _isTyping = isTyping;
        });
      }
    }
  }

  void _handleOnlineStatus(Map<String, dynamic> message) {
    final username = message['username'];
    final isOnline = message['is_online'] == true;

    if (username == widget.friend.username) {
      if (mounted) {
        setState(() {
          _friendOnline = isOnline;
        });
      }

      if (isOnline) {
        debugPrint('Amigo ficou online, verificando mensagens pendentes...');
        _checkPendingMessages();
      }
    }
  }

  Message? _createMessageFromMap(
      Map<String, dynamic> data, int? currentUserId) {
    try {
      final senderId = data['sender_id'];
      final receiverId = data['receiver_id'];
      final serverId = data['id'];
      final content = data['content'] ?? '';

      if (senderId == null || receiverId == null || currentUserId == null) {
        debugPrint('Dados incompletos para criar mensagem');
        return null;
      }

      final isMessageForThisChat =
          (senderId == currentUserId && receiverId == widget.friend.id) ||
              (receiverId == currentUserId && senderId == widget.friend.id);

      if (!isMessageForThisChat) {
        debugPrint(
            'Mensagem não é para este chat: currentUser=$currentUserId, friendId=${widget.friend.id}');
        return null;
      }

      int? messageId;
      if (serverId != null && serverId != 411) {
        messageId = serverId;
      } else {
        final uniqueString = '${content}_${data['timestamp']}_$senderId';
        messageId = uniqueString.hashCode;
        debugPrint('ID gerado localmente: $messageId para "$content"');
      }

      final isMine = senderId == currentUserId;
      final now = DateTime.now();

      return Message(
        id: messageId,
        senderId: senderId,
        receiverId: receiverId,
        content: content,
        timestamp: now,
        isDelivered: true,
        isMine: isMine,
        localId: null,
        isSentToServer: true,
        hasError: false,
      );
    } catch (e) {
      debugPrint('Erro ao criar mensagem: $e');
      debugPrint('Dados da mensagem: $data');
      return null;
    }
  }

  Future<void> _loadLocalMessages() async {
    if (_localStorage == null || _hasLoadedLocalMessages) return;

    try {
      _hasLoadedLocalMessages = true;

      final localMessages = await _localStorage!.getLocalConversationHistory(
        widget.friend.username,
        100,
      );

      final currentUserId =
          Provider.of<AuthProvider>(context, listen: false).userId;

      final messagesList = localMessages.map((msgData) {
        DateTime messageDate;
        try {
          messageDate = DateTime.parse(msgData['timestamp']);
        } catch (e) {
          messageDate = DateTime.now();
        }

        return Message(
          id: msgData['server_id'] ?? msgData['local_id']?.hashCode,
          senderId: msgData['sender_id'],
          receiverId: widget.friend.id,
          content: msgData['content'],
          timestamp: messageDate,
          isDelivered: msgData['is_delivered'] == 1,
          isMine: msgData['sender_id'] == currentUserId,
          localId: msgData['local_id'],
          isSentToServer: msgData['is_sent_to_server'] == 1,
          hasError: false,
        );
      }).toList();

      messagesList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (mounted) {
        setState(() {
          if (_messages.isEmpty) {
            _messages.addAll(messagesList);
          } else {
            for (final localMsg in messagesList) {
              final exists = _messages.any((existingMsg) {
                if (existingMsg.id != null && localMsg.id != null) {
                  return existingMsg.id == localMsg.id;
                }
                return existingMsg.content == localMsg.content &&
                    existingMsg.timestamp
                            .difference(localMsg.timestamp)
                            .inSeconds
                            .abs() <
                        2;
              });

              if (!exists) {
                _messages.add(localMsg);
              }
            }
            // Reordena tudo no final
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens locais: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncUnsentMessages() async {
    if (_localStorage == null) return;
  }

  void _checkPendingMessages() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.socketService.checkPendingMessages();
    } catch (e) {
      debugPrint('Erro ao verificar mensagens pendentes: $e');
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.userId;

    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    final now = DateTime.now();

    try {
      if (mounted) {
        setState(() {
          _messages.add(Message(
            id: null,
            senderId: currentUserId,
            receiverId: widget.friend.id,
            content: text,
            timestamp: now,
            isDelivered: false,
            isMine: true,
            localId:
                'local_${DateTime.now().millisecondsSinceEpoch}_$currentUserId',
            isSentToServer: false,
            hasError: false,
          ));
          _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        });
      }

      _messageController.clear();
      _scrollToBottom();

      final socketService = authProvider.socketService;

      final response = await socketService.sendMessage(
          widget.friend.username, text, widget.friend.idfriendship, widget.friend.id);

      if (response['success'] == true) {
      } else {
        debugPrint('Erro ao enviar mensagem: ${response['message']}');
      }
    } catch (e) {
      debugPrint('Erro ao enviar mensagem: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar mensagem: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _clearChatHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar Histórico?'),
        content: Text(
            'Deseja realmente apagar todas as mensagens com ${widget.friend.username}? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              await _localStorage!
                  .deleteConversationHistory(widget.friend.username);

              setState(() {
                _messages
                    .clear();
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Histórico apagado com sucesso.')),
              );
            },
            child: const Text('Apagar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  //! digitação
  void _onTextChanged(String text) {
    _typingDebounceTimer?.cancel();

    final hasText = text.isNotEmpty;

    if (!_isCurrentlyTyping && hasText) {
      _sendTypingStart();
      _isCurrentlyTyping = true;
    }

    _typingDebounceTimer = Timer(
      const Duration(milliseconds: _typingDebounceMs),
      () {
        if (mounted && _isCurrentlyTyping) {
          _sendTypingStop();
          _isCurrentlyTyping = false;
        }
      },
    );
  }

  void _sendTypingStart() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    socketService.sendTypingStart(widget.friend.username);
  }

  void _sendTypingStop() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    socketService.sendTypingStop(widget.friend.username);
  }

  void _clearTypingTimer() {
    _typingDebounceTimer?.cancel();
    if (_isCurrentlyTyping) {
      _sendTypingStop();
      _isCurrentlyTyping = false;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, 
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  //? definiciões do front
  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Nunca visto';

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) return 'Visto agora';
    if (difference.inMinutes < 60) {
      return 'Visto há ${difference.inMinutes} min';
    }
    if (difference.inHours < 24) return 'Visto há ${difference.inHours} h';
    if (difference.inDays < 7) return 'Visto há ${difference.inDays} dias';

    return 'Visto em ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
  }

  Widget _buildWhatsAppBubble(Message message) {
    final isMe = message.isMine;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 50 : 0, 
          right: isMe ? 0 : 50,
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[100] : Colors.blue[300],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(color: Colors.black87, fontSize: 16),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isDelivered ? Icons.done_all : Icons.done,
                      size: 14,
                      color: message.isDelivered ? Colors.blue : Colors.grey,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    final reversedMessages = _messages.reversed.toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      itemCount: reversedMessages.length,
      reverse: true,
      itemBuilder: (context, index) {
        final message = reversedMessages[index];
        return _buildWhatsAppBubble(message);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.friend.username,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            _isTyping
                ? Text(
                    'Digitando...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[600],
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Text(
                    _friendOnline || widget.friend.isOnline
                        ? 'Online'
                        : _formatLastSeen(widget.friend.lastSeen),
                    style: TextStyle(
                      fontSize: 12,
                      color: (_friendOnline || widget.friend.isOnline)
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(
                Icons.delete_sweep_outlined),
            onPressed: _clearChatHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Nenhuma mensagem ainda',
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              'Envie a primeira mensagem!',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : _buildChatList(),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _onTextChanged,
                    onSubmitted: (text) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Digite uma mensagem...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _typingDebounceTimer?.cancel();
    _typingTimer?.cancel();
    _clearTypingTimer();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}
