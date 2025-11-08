import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cliente/services/messagecrypo_servece.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final MessageCryptoService _messageCrypto = MessageCryptoService();

  Uint8List _getSecureRandom() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  // Gera um par de chaves ECC principais (para registro/login)
  Map<String, String> generateKeyPair() {
    final privateKey = _getSecureRandom();
    final publicKey = _calculatePublicKey(privateKey);

    return {
      'privateKey': base64Encode(privateKey),
      'publicKey': base64Encode(publicKey),
    };
  }

  // Gera par DHE efêmero com Ed25519 (32 bytes)
  Map<String, String> generateDHEKeyPair() {
    final privateKey = _getSecureRandom();
    final publicKey = _calculatePublicKey(privateKey);

    return {
      'privateKey': base64Encode(privateKey),
      'publicKey': base64Encode(publicKey),
    };
  }

  // Simula cálculo de chave pública Ed25519
  Uint8List _calculatePublicKey(Uint8List privateKey) {
    final hash = sha256.convert(privateKey).bytes;
    return Uint8List.fromList(hash.sublist(0, 32));
  }

  // Calcula segredo compartilhado para Ed25519
  Uint8List computeSharedSecretBytes({
    required String ownPrivateBase64,
    required String peerPublicBase64,
    required String saltBase64,
  }) {
    try {
      final ownPrivate = base64Decode(ownPrivateBase64);
      final ownPublic =
          _calculatePublicKey(ownPrivate); 
      final salt = base64Decode(saltBase64);

      final combined = Uint8List.fromList([...ownPublic, ...salt]);

      final sharedSecret = sha256.convert(combined).bytes;

      return Uint8List.fromList(sharedSecret.sublist(0, 32));
    } catch (e) {
      debugPrint('❌ Erro ao calcular segredo compartilhado: $e');
      rethrow;
    }
  }

  // Adicione este helper para converter bytes para hex
  String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Encode(bytes);
  }

  // Deriva chaves de sessão usando HKDF-SHA256
  Map<String, Uint8List> deriveKeysFromSharedSecret({
    required Uint8List sharedSecret,
    required String saltBase64,
    List<int>? info,
  }) {
    final hkdfInfo = info ?? utf8.encode('session_keys_v1');
    final salt = saltBase64.isEmpty ? Uint8List(0) : base64Decode(saltBase64);

    final prk = _hkdfExtract(salt: salt, ikm: sharedSecret);

    final okm = _hkdfExpand(prk: prk, info: hkdfInfo, length: 64);

    final encKey = okm.sublist(0, 32);
    final hmacKey = okm.sublist(32, 64);

    // Define as chaves no serviço de criptografia de mensagens
    _messageCrypto.setSessionKeys(
      encryptionKey: Uint8List.fromList(encKey),
      hmacKey: Uint8List.fromList(hmacKey),
    );

    return {
      'encryptionKey': Uint8List.fromList(encKey),
      'hmacKey': Uint8List.fromList(hmacKey),
    };
  }

  // --- HKDF implementation ---
  Uint8List _hkdfExtract({required Uint8List salt, required Uint8List ikm}) {
    final hmac = Hmac(sha256, salt);
    final prkBytes = hmac.convert(ikm).bytes;
    return Uint8List.fromList(prkBytes);
  }

  Uint8List _hkdfExpand({
    required Uint8List prk,
    required List<int> info,
    required int length,
  }) {
    final hmac = Hmac(sha256, prk);
    final List<int> okm = [];
    var previous = <int>[];
    var iterations = (length / 32).ceil();

    for (var i = 1; i <= iterations; i++) {
      final input = <int>[];
      if (previous.isNotEmpty) input.addAll(previous);
      input.addAll(info);
      input.add(i);

      final t = hmac.convert(Uint8List.fromList(input)).bytes;
      okm.addAll(t);
      previous = t;
    }

    return Uint8List.fromList(okm.sublist(0, length));
  }

  // Criptografa uma mensagem para envio
  Map<String, String> encryptMessage(String plaintext) {
    return _messageCrypto.encryptMessage(plaintext);
  }

  // Descriptografa uma mensagem recebida
  String decryptMessage(Map<String, String> encryptedMessage) {
    return _messageCrypto.decryptMessage(encryptedMessage);
  }

  // Verifica se a criptografia de mensagens está pronta
  bool get isMessageCryptoReady => _messageCrypto.isReady;

  // Limpa as chaves de sessão
  void clearSessionKeys() {
    _messageCrypto.clearSessionKeys();
  }
}
