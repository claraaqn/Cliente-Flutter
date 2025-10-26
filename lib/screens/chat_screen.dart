import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cliente/database_helper.dart';
import 'package:cliente/models/chat_models.dart';
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
    debugPrint('🚀 ChatScreen iniciado para: ${widget.friend.username}');
    _initializeChat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localStorage == null) {
      _localStorage = Provider.of<LocalStorageService>(context, listen: false);
      debugPrint('✅ LocalStorageService obtido com sucesso');
    }
  }

  void _initializeChat() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    _messageSubscription = socketService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocalMessages();
      _syncUnsentMessages();
      _checkPendingMessages();
    });
  }

//! mensagens
  void _handleIncomingMessage(Map<String, dynamic> message) {
    final action = message['action'];
    debugPrint('📨 Mensagem recebida: $action');

    switch (action) {
      case 'new_message':
        _handleNewMessage(message);
        break;
      case 'user_typing':
        _handleTypingIndicator(message);
        break;
      case 'user_online_status':
        _handleOnlineStatus(message);
        break;
    }
  }

  void _handleNewMessage(Map<String, dynamic> message) {
    try {
      final currentUserId =
          Provider.of<AuthProvider>(context, listen: false).userId;
      debugPrint('📨 Processando nova mensagem: ${message['content']}');

      final newMessage = _createMessageFromMap(message, currentUserId);

      if (newMessage != null) {
        debugPrint(
            '✅ Mensagem criada: "${newMessage.content}" - ID: ${newMessage.id}');

        final isDuplicate = _messages.any((msg) {
          final timeDiff =
              msg.timestamp.difference(newMessage.timestamp).inSeconds.abs();
          final isDuplicateByContent = msg.content == newMessage.content &&
              msg.senderId == newMessage.senderId &&
              timeDiff < 3;

          if (isDuplicateByContent) {
            debugPrint(
                '⚠️ Duplicata detectada: "${msg.content}" - timeDiff: $timeDiff segundos');
          }

          return isDuplicateByContent;
        });

        if (!isDuplicate) {
          if (mounted) {
            setState(() {
              _messages.add(newMessage);
              _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            });
            _scrollToBottom();
            debugPrint('✅ Nova mensagem ADICIONADA: "${newMessage.content}"');
            debugPrint('📊 Total de mensagens: ${_messages.length}');

            for (var i = 0; i < _messages.length; i++) {
              debugPrint(
                  '🔄 Ordem [$i]: "${_messages[i].content}" - ${_messages[i].timestamp}');
            }

            _saveMessageLocally(newMessage);
          }
        } else {
          debugPrint('⚠️ Mensagem duplicada IGNORADA: "${newMessage.content}"');
          _saveMessageLocally(newMessage);
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao processar nova mensagem: $e');
    }
  }

  Future<void> _saveMessageLocally(Message message) async {
    try {
      final chatMessage = ChatMessage(
        from: message.senderId.toString(),
        content: message.content,
        timestamp: message.timestamp,
      );
      await DatabaseHelper.instance
          .insertMessage(chatMessage, widget.friend.username);
      debugPrint('💾 Mensagem salva localmente: ${message.content}');
    } catch (e) {
      debugPrint('❌ Erro ao salvar mensagem localmente: $e');
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
      debugPrint('✍️ $username está ${isTyping ? 'digitando' : 'parou'}');
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

      debugPrint('🟢 $username está ${isOnline ? 'online' : 'offline'}');

      if (isOnline) {
        debugPrint('🔄 Amigo ficou online, verificando mensagens pendentes...');
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
        debugPrint('❌ Dados incompletos para criar mensagem');
        return null;
      }

      final isMessageForThisChat =
          (senderId == currentUserId && receiverId == widget.friend.id) ||
              (receiverId == currentUserId && senderId == widget.friend.id);

      if (!isMessageForThisChat) {
        debugPrint(
            '❌ Mensagem não é para este chat: currentUser=$currentUserId, friendId=${widget.friend.id}');
        return null;
      }

      int? messageId;
      if (serverId != null && serverId != 411) {
        messageId = serverId;
      } else {
        final uniqueString = '${content}_${data['timestamp']}_$senderId';
        messageId = uniqueString.hashCode;
        debugPrint('🆔 ID gerado localmente: $messageId para "$content"');
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
      debugPrint('❌ Erro ao criar mensagem: $e');
      debugPrint('❌ Dados da mensagem: $data');
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

      final now = DateTime.now();

      final messagesList = localMessages.map((msgData) {
        return Message(
          id: msgData['server_id'] ?? msgData['local_id']?.hashCode,
          senderId: msgData['sender_id'],
          receiverId: widget.friend.id, // Valor fallback
          content: msgData['content'],
          timestamp: now,
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
              final exists = _messages.any((existingMsg) =>
                  existingMsg.content == localMsg.content &&
                  existingMsg.timestamp
                          .difference(localMsg.timestamp)
                          .inSeconds
                          .abs() <
                      3);

              if (!exists) {
                _messages.add(localMsg);
              }
            }
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar mensagens locais: $e');
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
    debugPrint('🔄 Sincronizando mensagens não enviadas...');
  }

  void _checkPendingMessages() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.socketService.checkPendingMessages();
      debugPrint('✅ Verificação de mensagens pendentes concluída');
    } catch (e) {
      debugPrint('❌ Erro ao verificar mensagens pendentes: $e');
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

    if (widget.friend.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destinatário inválido')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    final now = DateTime.now();

    try {
      final sentMessage = ChatMessage(
        from: currentUserId.toString(),
        content: text,
        timestamp: now,
      );
      await DatabaseHelper.instance
          .insertMessage(sentMessage, widget.friend.username);

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
      final response =
          await socketService.sendMessage(widget.friend.username, text);

      if (response['success'] == true) {
        debugPrint('✅ Mensagem enviada para o servidor');
      } else {
        debugPrint('❌ Erro ao enviar mensagem: ${response['message']}');
      }
    } catch (e) {
      debugPrint('❌ Erro ao enviar mensagem: $e');
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

    try {
      socketService.sendTypingStart(widget.friend.username);
      debugPrint('✍️ Start typing enviado para ${widget.friend.username}');
    } catch (e) {
      debugPrint('❌ Erro ao enviar typing start: $e');
    }
  }

  void _sendTypingStop() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      socketService.sendTypingStop(widget.friend.username);
      debugPrint('🛑 Stop typing enviado para ${widget.friend.username}');
    } catch (e) {
      debugPrint('❌ Erro ao enviar typing stop: $e');
    }
  }

  void _clearTypingTimer() {
    _typingDebounceTimer?.cancel();
    if (_isCurrentlyTyping) {
      _sendTypingStop();
      _isCurrentlyTyping = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _messages.isNotEmpty) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
    if (difference.inMinutes < 60)
      return 'Visto há ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'Visto há ${difference.inHours} h';
    if (difference.inDays < 7) return 'Visto há ${difference.inDays} dias';

    return 'Visto em ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
  }

  Widget _buildMessageBubble(Message message) {
    final isMe = message.isMine;
    debugPrint('🎨 BUILDING BUBBLE: "${message.content}" - isMine: $isMe');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue[100],
              child: Text(
                widget.friend.username[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          Flexible(
            child: Container(
              margin: EdgeInsets.only(
                left: isMe ? 60 : 8,
                right: isMe ? 8 : 60,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue[500] : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isMe
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.hasError
                              ? Icons.error
                              : (message.isDelivered
                                  ? Icons.done_all
                                  : Icons.done),
                          size: 12,
                          color: message.hasError
                              ? Colors.red[200]
                              : (message.isDelivered
                                  ? Colors.white70
                                  : Colors.white30),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green[100],
              child: Icon(Icons.person, size: 16, color: Colors.green[700]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedMessages = List<Message>.from(_messages)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

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
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // TODO: Mostrar informações do contato
            },
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
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: sortedMessages.length,
                        reverse: false,
                        itemBuilder: (context, index) {
                          final message = sortedMessages[index];
                          return _buildMessageBubble(message);
                        },
                      ),
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
