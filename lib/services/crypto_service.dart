import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cliente/services/messagecrypo_servece.dart';
import 'package:flutter/widgets.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();
  final sha256 = Sha256();
  final _x25519 = X25519();
  final _ed25519 = Ed25519();

  final MessageCryptoService _messageCrypto = MessageCryptoService();
  final Map<int, MessageCryptoService> _friendSessionKeys = {};

  Future<Map<String, String>> generateKeyPair() async {
    try {
      final keyPair = await _ed25519.newKeyPair();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();

      return {
        'privateKey': base64Encode(privateKeyBytes),
        'publicKey': base64Encode(publicKey.bytes),
      };
    } catch (e) {
      debugPrint('Erro ao gerar par de chaves Ed25519: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> generateKeyPairFromPrivate(
      String privateKeyB64) async {
    try {
      final privateKeyBytes = base64Decode(privateKeyB64);

      final keyPair = await _ed25519.newKeyPairFromSeed(privateKeyBytes);
      final publicKey = await keyPair.extractPublicKey();

      return {
        'privateKey': privateKeyB64,
        'publicKey': base64Encode(publicKey.bytes),
      };
    } catch (e) {
      debugPrint('Erro ao gerar key pair from private: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> generateDHEKeyPair() async {
    final keyPar = await _x25519.newKeyPair();

    final privateKeyBytes = await keyPar.extractPrivateKeyBytes();
    final publicKey = await keyPar.extractPublicKey();

    return {
      'privateKey': base64Encode(privateKeyBytes),
      'publicKey': base64Encode(publicKey.bytes),
    };
  }

  Future<Uint8List> computeSharedSecretBytes({
    required String ownPrivateBase64,
    required String peerPublicBase64,
  }) async {
    try {
      final ownPrivate = base64Decode(ownPrivateBase64);
      final peerPublic = base64Decode(peerPublicBase64);

      final keyPair = await _x25519.newKeyPairFromSeed(ownPrivate);

      final peerPublicKey =
          SimplePublicKey(peerPublic, type: KeyPairType.x25519);

      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: peerPublicKey,
      );

      final secretBytesList = await sharedSecret.extractBytes();
      final secretBytes = Uint8List.fromList(secretBytesList);

      return secretBytes;
    } catch (e) {
      debugPrint('Erro ao calcular segredo compartilhado: $e');
      rethrow;
    }
  }

  String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Encode(Uint8List.fromList(bytes));
  }

  Future<Map<String, Uint8List>> deriveKeysFromSharedSecret({
    required Uint8List sharedSecret,
    required String saltBase64,
    required List<int> info,
  }) async {
    try {
      final salt = base64Decode(saltBase64);

      final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 64);

      final keyMaterial = await hkdf.deriveKey(
        secretKey: SecretKey(sharedSecret),
        nonce: salt,
        info: info,
      );

      final keyBytes = await keyMaterial.extractBytes();

      final encryptionKey = Uint8List.fromList(keyBytes.sublist(0, 32));
      final hmacKey = Uint8List.fromList(keyBytes.sublist(32, 64));

      return {
        'encryption': encryptionKey,
        'hmac': hmacKey,
      };
    } catch (e) {
      debugPrint('Erro ao derivar chaves: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> encryptMessage(String plaintext) {
    return _messageCrypto.encryptMessage(plaintext);
  }

  Future<String> decryptMessage(Map<String, String> encryptedMessage) {
    return _messageCrypto.decryptMessage(encryptedMessage);
  }

  bool get isMessageCryptoReady => _messageCrypto.isReady;

  void setSessionKeys(
      {required Uint8List encryptionKey, required Uint8List hmacKey}) {
    _messageCrypto.setSessionKeys(
      encryptionKey: encryptionKey,
      hmacKey: hmacKey,
    );
  }

  void setSessionKeysFriends(
      {required int friendshipId,
      required Uint8List encryptionKey,
      required Uint8List hmacKey}) {
    final service = MessageCryptoService();
    service.setSessionKeys(encryptionKey: encryptionKey, hmacKey: hmacKey);

    _friendSessionKeys[friendshipId] = service;
  }

  Future<Map<String, String>> encryptMessageFriend(
      String plaintext, int friendshipId) async {
    final service = _friendSessionKeys[friendshipId];
    if (service == null || !service.isReady) {
      throw Exception(
          "Sessão P2P não encontrada ou não iniciada para amizade $friendshipId");
    }
    return service.encryptMessage(plaintext);
  }

  Future<String> decryptMessageFriend(
      Map<String, String> encryptedMessage, int friendshipId) async {
    final service = _friendSessionKeys[friendshipId];
    if (service == null || !service.isReady) {
      throw Exception(
          "Chaves de sessão não carregadas para amizade $friendshipId");
    }
    return service.decryptMessage(encryptedMessage);
  }

  bool isFriendSessionReady(int friendshipId) {
    return _friendSessionKeys.containsKey(friendshipId) &&
        _friendSessionKeys[friendshipId]!.isReady;
  }

  void clearFriendSession(int friendshipId) {
    if (_friendSessionKeys.containsKey(friendshipId)) {
      _friendSessionKeys.remove(friendshipId);
      debugPrint("🧹 Cache de chaves limpo para amizade $friendshipId");
    }
  }

  void clearSessionKeys() {
    _messageCrypto.clearSessionKeys();
  }

  Future<String> signData(Uint8List data, String privateKeyB64) async {
    try {
      Uint8List privateKeyBytes = base64Decode(privateKeyB64);

      final keyPair = await _ed25519.newKeyPairFromSeed(privateKeyBytes);

      final signature = await _ed25519.sign(
        data,
        keyPair: keyPair,
      );

      return base64Encode(signature.bytes);
    } catch (e) {
      debugPrint('Erro ao assinar dados: $e');
      rethrow;
    }
  }

  Future<bool> verifySignature({
    required Uint8List data,
    required String signatureB64,
    required String publicKeyB64,
  }) async {
    try {
      final signatureBytes = base64Decode(signatureB64);
      final publicKeyBytes = base64Decode(publicKeyB64);

      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );

      final isVerified = await _ed25519.verify(
        data,
        signature: signature,
      );

      debugPrint(' Assinatura válida: $isVerified');
      return isVerified;
    } catch (e) {
      debugPrint('Erro ao verificar assinatura: $e');
      return false;
    }
  }
}
