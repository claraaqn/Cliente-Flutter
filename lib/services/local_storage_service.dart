import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    } else {
      debugPrint('Mensagem já existe: ${message['id']} - ignorando duplicata');
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

  Future<int> deleteConversationHistory(String otherUsername) async {
    try {
      final db = await database;
      int count = await db.delete(
        'messages',
        where: 'receiver_username = ? OR sender_username = ?',
        whereArgs: [otherUsername, otherUsername],
      );
      debugPrint(
          '🗑️ Histórico com $otherUsername apagado: $count mensagens removidas.');
      return count;
    } catch (e) {
      debugPrint('❌ Erro ao apagar histórico: $e');
      return 0;
    }
  }

  Future<int?> getFriendshipId(int friendId) async {
    final db = await database;
    final result = await db.query(
      'friends',
      columns: ['id_friendship'],
      where: 'user_id = ?',
      whereArgs: [friendId],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['id_friendship'] as int?;
    }
    return null;
  }

  Future<void> savePrivateKey(String privateKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('private_key', privateKey);
      debugPrint('Chave privada salva com sucesso');
    } catch (e) {
      debugPrint('Erro ao salvar chave privada: $e');
      throw Exception('Falha ao salvar chave privada');
    }
  }

  Future<String?> getPrivateKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('private_key');
    } catch (e) {
      debugPrint('Erro ao recuperar chave privada: $e');
      return null;
    }
  }

  Future<void> clearPrivateKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('private_key');
      debugPrint('Chave privada removida');
    } catch (e) {
      debugPrint('Erro ao remover chave privada: $e');
    }
  }

  Future<void> saveUserCredentials(String username, String privateKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      await prefs.setString('private_key', privateKey);
      await prefs.setBool('has_credentials', true);
      debugPrint('Credenciais salvas para usuário: $username');
    } catch (e) {
      debugPrint('Erro ao salvar credenciais: $e');
      throw Exception('Falha ao salvar credenciais');
    }
  }

  Future<void> initForUser(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt("userID", userId);

      await database;
    } catch (e) {
      debugPrint("[LocalStorage] Erro ao inicializar banco: $e");
    }
  }

  Future<int?> getuserdd(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(userId as String);
  }

  Future<Map<String, String>?> getUserCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      final privateKey = prefs.getString('private_key');

      if (username != null && privateKey != null) {
        debugPrint('Credenciais recuperadas para: $username');
        return {
          'username': username,
          'privateKey': privateKey,
        };
      }
      debugPrint('Nenhuma credencial encontrada');
      return null;
    } catch (e) {
      debugPrint('Erro ao recuperar credenciais: $e');
      return null;
    }
  }

  Future<bool> hasCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('has_credentials') ?? false;
    } catch (e) {
      debugPrint('Erro ao verificar credenciais: $e');
      return false;
    }
  }

  Future<void> clearUserCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('username');
      await prefs.remove('private_key');
      await prefs.remove('has_credentials');
    } catch (e) {
      debugPrint('Erro ao remover credenciais: $e');
    }
  }

  Future<void> saveFriendRequestKeySender(
      int reciverId, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("friend_req_${reciverId}_privA", privateKey);
  }

  Future<void> saveFriendRequestKeyReceiver(
      int reciverId, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("friend_req_${reciverId}_privB", privateKey);
  }

  Future<void> saveSharedKey(int reciverId, String sharedKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("shared_key_$reciverId", sharedKey);
  }

  Future<String?> getFriendRequestPrivateKeyReceiver(int reciverId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("friend_req_${reciverId}_privB");
  }

  Future<String?> getFriendRequestPrivateKeySender(int reciverId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("friend_req_${reciverId}_privA");
  }

  Future<String?> getSharedKey(int reciverId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("shared_key_$reciverId");
  }

  Future<void> clearHandshakeData(int reciverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("friend_req_${reciverId}_privA");
    await prefs.remove("friend_req_${reciverId}_privB");
    await prefs.remove("shared_key_$reciverId");
  }

  Future<void> saveMyPrivateKeyDHE(int myID, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("my_priv_DHE$myID", privateKey);
  }

  Future<String?> getMyPrivateKeyDH(int myID) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("my_priv_DHE$myID");
  }

  Future<void> saveMyPublicteKeyDHE(int myID, String publicKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("my_pub_DHE$myID", publicKey);
  }

  Future<String?> getMyPublicKeyDHE(int myID) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("my_pub_DHE$myID");
  }

  Future<void> saveFriendSessionKeys(
      int idFriendship, String encKey, String hmacKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("session_enc_$idFriendship", encKey);
    await prefs.setString("session_hmac_$idFriendship", hmacKey);
    debugPrint("Chave de amigos salvas");
  }

  Future<Map<String, String>?> getFriendSessionKeys(int idFriendship) async {
    final prefs = await SharedPreferences.getInstance();
    final enc = prefs.getString("session_enc_$idFriendship");
    final hmac = prefs.getString("session_hmac_$idFriendship");

    if (enc != null && hmac != null) {
      return {'encryption': enc, 'hmac': hmac};
    }
    return null;
  }

  Future<void> saveMyPrivateKey(int myID, String privateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("my_priv_ed25519$myID", privateKey);
  }

  Future<String?> getMyPrivateKey(int myID) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("my_priv_ed25519$myID");
  }

  Future<void> saveMyPublicteKey(int myID, String publicKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("my_pub_ed25519$myID", publicKey);
  }

  Future<String?> getMyPublicKey(int myID) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("my_pub_ed25519$myID");
  }

  Future<void> saveFriendPublicKey(int friendId, String publicKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("friend_pub_ed25519$friendId", publicKey);
  }

  Future<String?> getFriendPublicKey(int friendId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("friend_pub_ed25519$friendId");
  }

  static const String _userIdKey = 'user_id';

  Future<void> saveUserId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, id);
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  Future<void> deleteFriendSessionKeys(int friendshipId) async {
    final db = await database;
    try {
      await db.delete(
        'friend_session_keys',
        where: 'id_friendship = ?',
        whereArgs: [friendshipId],
      );
      debugPrint(
          "Chaves de sessão deletadas do DB para amizade: $friendshipId");
    } catch (e) {
      debugPrint("Erro ao deletar chaves de sessão: $e");
    }
  }
}
