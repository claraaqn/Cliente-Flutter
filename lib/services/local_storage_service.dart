import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalStorageService {
  static Database? _database;
  

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'chat_app.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT UNIQUE,
        server_id INTEGER,
        sender_id INTEGER,
        sender_username TEXT,
        receiver_id INTEGER,
        receiver_username TEXT,
        content TEXT,
        timestamp TEXT,
        is_delivered INTEGER DEFAULT 0,
        is_sent_to_server INTEGER DEFAULT 0,
        is_read INTEGER DEFAULT 0,
        message_type TEXT DEFAULT 'text'
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT UNIQUE,
        receiver_username TEXT,
        content TEXT,
        timestamp TEXT,
        retry_count INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> saveReceivedMessage(Map<String, dynamic> message) async {
    final db = await database;

    final existing = await db.query(
      'messages',
      where: 'server_id = ?',
      whereArgs: [message['id']],
    );

    if (existing.isEmpty) {
      int isDelivered = (message['is_delivered'] == true) ? 1 : 0;
      int isRead = (message['is_read'] == true) ? 1 : 0;

      await db.insert('messages', {
        'server_id': message['id'],
        'sender_id': message['sender_id'],
        'sender_username': message['sender_username'],
        'receiver_username': message['receiver_username'],
        'content': message['content'],
        'timestamp': message['timestamp'],
        'is_delivered': isDelivered,
        'is_sent_to_server': 1,
        'is_read': isRead,
      });

      debugPrint('💾 Mensagem salva localmente: ${message['id']}');
    } else {
      debugPrint(
          '💾 Mensagem já existe: ${message['id']} - ignorando duplicata');
    }
  }

  Future<void> markMessageAsSent(String localId, int serverId) async {
    final db = await database;
    await db.update(
      'messages',
      {
        'server_id': serverId,
        'is_sent_to_server': 1,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsentMessages() async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'is_sent_to_server = ?',
      whereArgs: [0],
    );
  }

  Future<List<Map<String, dynamic>>> getLocalConversationHistory(
      String otherUsername, int limit) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'receiver_username = ? OR sender_username = ?',
      whereArgs: [otherUsername, otherUsername],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<int> saveMessageLocally(Map<String, dynamic> message) async {
    final db = await database;

    String localId =
        'local_${DateTime.now().millisecondsSinceEpoch}_${message['sender_id']}';

    int isDelivered = (message['is_delivered'] == true) ? 1 : 0;

    return await db.insert('messages', {
      'local_id': localId,
      'sender_id': message['sender_id'],
      'sender_username': message['sender_username'],
      'receiver_username': message['receiver_username'],
      'content': message['content'],
      'timestamp': message['timestamp'],
      'is_delivered': isDelivered,
      'is_sent_to_server': 0,
      'is_read': 0,
    });
  }

  Future<String?> getLastMessageTimestamp(String username) async {
    final db = await database;
    final result = await db.query(
      'messages',
      where: 'receiver_username = ? OR sender_username = ?',
      whereArgs: [username, username],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['timestamp'] as String;
    }
    return null;
  }

}
