import 'dart:async';
import 'dart:developer' as console;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cliente/providers/auth_provider.dart';
import 'package:cliente/models/message.dart';
import 'package:cliente/models/friend.dart';

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

  Timer? _typingTimer;
  static const int _typingTimeoutMs = 1500; // 1.5 segundos
  bool _isSendingTypingStart = false; // Novo estado para controlar o envio

  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _loadMessages();
  }

  void _initializeChat() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    // CORREÇÃO: Usar subscription para gerenciar melhor
    _messageSubscription = socketService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    final action = message['action'];

    switch (action) {
      case 'new_message':
        _handleNewMessage(message);
        break;
      case 'user_typing':
        _handleTypingIndicator(message);
        break;
      case 'user_status_change':
        _handleUserStatusChange(message);
        break;
    }
  }

  void _handleNewMessage(Map<String, dynamic> message) {
    try {
      final currentUserId =
          Provider.of<AuthProvider>(context, listen: false).userId;
      final currentUserIdInt = currentUserId;

      final newMessage = _createMessageFromMap(message, currentUserIdInt);

      if (newMessage != null) {
        _addNewMessage(newMessage);

        _scrollToBottom();
      }
    } catch (e) {
      console.log('❌ Erro ao processar nova mensagem: $e');
    }
  }

  Message? _createMessageFromMap(
      Map<String, dynamic> data, int? currentUserId) {
    try {
      // Funções de conversão locais
      int? safeParseInt(dynamic value) {
        if (value == null) return null;
        if (value is int) return value;
        if (value is String) return int.tryParse(value);
        return null;
      }

      String safeParseString(dynamic value) {
        if (value == null) return '';
        if (value is String) return value;
        return value.toString();
      }

      DateTime safeParseDateTime(dynamic value) {
        if (value == null) return DateTime.now();
        if (value is DateTime) return value;
        if (value is String) {
          try {
            return DateTime.parse(value);
          } catch (e) {
            return DateTime.now();
          }
        }
        return DateTime.now();
      }

      // CORREÇÃO: Extrair IDs de forma mais robusta
      final senderId =
          safeParseInt(data['sender_id']) ?? safeParseInt(data['senderId']);
      final receiverId =
          safeParseInt(data['receiver_id']) ?? safeParseInt(data['receiverId']);

      if (senderId == null || receiverId == null) {
        console.log('❌ IDs inválidos: sender=$senderId, receiver=$receiverId');
        console.log('📨 Dados da mensagem: $data');
        return null;
      }

      // CORREÇÃO: Verificar se a mensagem é para este chat
      final isMessageForThisChat =
          (senderId == widget.friend.id && receiverId == currentUserId) ||
              (receiverId == widget.friend.id && senderId == currentUserId);

      if (!isMessageForThisChat) {
        console
            .log('❌ Mensagem não é para este chat: $senderId -> $receiverId');
        console
            .log('👥 Chat atual: Eu=$currentUserId, Amigo=${widget.friend.id}');
        return null;
      }

      console.log('✅ Nova mensagem recebida em tempo real: ${data['content']}');

      return Message(
        id: safeParseInt(data['id']),
        senderId: senderId,
        receiverId: receiverId,
        content: safeParseString(data['content']),
        timestamp: safeParseDateTime(data['timestamp']),
        isDelivered: true,
        isMine: senderId == currentUserId,
      );
    } catch (e) {
      console.log('❌ Erro ao criar mensagem: $e');
      return null;
    }
  }

  Future<void> _loadMessages() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      final response = await socketService.getConversationHistory(
        widget.friend.id.toString(),
        limit: 50,
      );

      if (response['success'] == true && mounted) {
        final currentUserId = authProvider.userId.toString();
        final currentUserIdInt = int.tryParse(currentUserId);

        final messagesData = response['data'];
        List<Message> messagesList = [];

        if (messagesData is List) {
          messagesList = messagesData
              .map((msgJson) {
                try {
                  final message =
                      _createMessageFromMap(msgJson, currentUserIdInt);
                  if (message != null) {
                    return message.copyWith(
                      isMine: message.senderId == currentUserIdInt,
                    );
                  }
                  return null;
                } catch (e) {
                  console.log('❌ Erro ao converter mensagem: $e');
                  return null;
                }
              })
              .whereType<Message>()
              .toList();

          // CORREÇÃO: Ordenar mensagens por timestamp (mais antigas primeiro)
          messagesList.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        }

        setState(() {
          _messages.clear();
          _messages.addAll(messagesList);
          _isLoading = false;
        });

        _scrollToBottom();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      console.log('❌ Erro ao carregar mensagens: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleTypingIndicator(Map<String, dynamic> message) {
    final userId = message['user_id']?.toString();
    final isTyping = message['is_typing'] == true;

    if (userId == widget.friend.id.toString()) {
      if (mounted) {
        setState(() {
          _isTyping = isTyping;
        });
      }
    }
  }

  void _handleUserStatusChange(Map<String, dynamic> message) {
    // a qualquer momento
  }

  Future<void> _sendMessage() async {
    // CORREÇÃO: Validações mais robustas
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    // CORREÇÃO: Verificar autenticação
    if (authProvider.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado')),
      );
      return;
    }

    // CORREÇÃO: Verificar friend.username
    if (widget.friend.username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destinatário inválido')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    _messageController.clear();

    try {
      // CORREÇÃO: Adicionar mensagem localmente
      final newMessage = Message(
        id: null,
        senderId: authProvider.userId!,
        receiverId: widget.friend.id,
        content: content,
        timestamp: DateTime.now(),
        isDelivered: false,
        isMine: true,
      );

      _addNewMessage(newMessage);

      // CORREÇÃO: Enviar mensagem com tratamento de erro
      final response = await socketService.sendMessage(
        widget.friend.username,
        content,
      );

      if (response['success'] == true && mounted) {
        // Atualizar mensagem com ID do servidor
        final messageIdStr = response['data']?['message_id']?.toString();
        if (messageIdStr != null) {
          final messageId = int.tryParse(messageIdStr);
          if (messageId != null) {
            final messageIndex = _messages.indexWhere((msg) => msg.id == null);
            if (messageIndex != -1) {
              setState(() {
                _messages[messageIndex] = _messages[messageIndex].copyWith(
                  id: messageId, // Agora é int
                  isDelivered: true,
                );
              });
            }
          } else {
            console.log('❌ message_id inválido: $messageIdStr');
          }
        }
      } else {
        // CORREÇÃO: Marcar mensagem como erro
        final errorMessage = response['message'] ?? 'Erro ao enviar mensagem';
        final messageIndex = _messages.indexWhere((msg) => msg.id == null);
        if (messageIndex != -1 && mounted) {
          setState(() {
            _messages[messageIndex] = _messages[messageIndex].copyWith(
              hasError: true,
            );
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        }
      }
    } catch (e) {
      console.log('❌ Erro ao enviar mensagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );

        // Marcar mensagem como erro
        final messageIndex = _messages.indexWhere((msg) => msg.id == null);
        if (messageIndex != -1) {
          setState(() {
            _messages[messageIndex] = _messages[messageIndex].copyWith(
              hasError: true,
            );
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _addNewMessage(Message message) {
    if (mounted) {
      setState(() {
        _messages.add(message);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
      _scrollToBottom();
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

  void _onTypingStarted() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      socketService.sendTypingStart(widget.friend.username);
    } catch (e) {
      console.log('❌ Erro ao enviar typing start: $e');
    }
  }

  void _onTypingStopped() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketService = authProvider.socketService;

    try {
      socketService.sendTypingStop(widget.friend.username);
    } catch (e) {
      console.log('❌ Erro ao enviar typing stop: $e');
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
    if (difference.inMinutes < 60)
      return 'Visto há ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'Visto há ${difference.inHours} h';
    if (difference.inDays < 7) return 'Visto há ${difference.inDays} dias';

    return 'Visto em ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
  }

  Widget _buildMessageBubble(Message message) {
    final isMe = message.isMine;

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
                    widget.friend.isOnline
                        ? 'Online'
                        : _formatLastSeen(widget.friend.lastSeen),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          widget.friend.isOnline ? Colors.green : Colors.grey,
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
              // TODO: Opção de excluit conversa
              // TODO: Acabar amizade
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
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          
                          return _buildMessageBubble(_messages[index]);
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
                    onChanged: (text) {
                      if (text.isNotEmpty && !_isSendingTypingStart) {
                        _onTypingStarted();
                        _isSendingTypingStart = true;
                      }

                      _typingTimer?.cancel();
                      _typingTimer = Timer(
                          const Duration(milliseconds: _typingTimeoutMs), () {
                        if (text.isEmpty || !mounted) return;
                        _onTypingStopped();
                        _isSendingTypingStart = false;
                      });

                      if (text.isEmpty && _isSendingTypingStart) {
                        _typingTimer?.cancel();
                        _onTypingStopped();
                        _isSendingTypingStart = false;
                      }
                    },
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
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }
}
