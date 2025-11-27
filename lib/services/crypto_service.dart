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

  final MessageCryptoService _messageCrypto = MessageCryptoService();

  Uint8List _getSecureRandom() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  // Gera um par de chaves ECC principais (para registro/login)
  Future<Map<String, String>> generateKeyPair() async {
    final privateKey = _getSecureRandom();
    final publicKey = await _calculatePublicKey(privateKey);

    return {
      'privateKey': base64Encode(privateKey),
      'publicKey': base64Encode(publicKey),
    };
  }

  // Gera par DHE efêmero com X25519  (32 bytes)
  Future<Map<String, String>> generateDHEKeyPair() async {
    final keyPar = await _x25519.newKeyPair();

    final privateKeyBytes = await keyPar.extractPrivateKeyBytes();
    final publicKey = await keyPar.extractPublicKey();

    return {
      'privateKey': base64Encode(privateKeyBytes),
      'publicKey': base64Encode(publicKey.bytes),
    };
  }

  // Simula cálculo de chave pública
  Future<Uint8List> _calculatePublicKey(Uint8List privateKey) async {
    final hash = await sha256.hash(privateKey);
    return Uint8List.fromList(hash.bytes.sublist(0, 32));
  }

  // Calcula segredo compartilhado
  Future<Uint8List> computeSharedSecretBytes({
    required String ownPrivateBase64,
    required String peerPublicBase64,
  }) async {
    try {
      final ownPrivate = base64Decode(ownPrivateBase64);
      final peerPublic = base64Decode(peerPublicBase64);

      debugPrint('🔄 Calculando segredo compartilhado:');
      debugPrint('   Chave privada: ${base64Encode(ownPrivate)}');
      debugPrint('   Chave pública do peer: ${base64Encode(peerPublic)}');

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
    return base64Encode(Uint8List.fromList(bytes));
  }

  // Deriva chaves de sessão usando HKDF-SHA256
  Future<Map<String, Uint8List>> deriveKeysFromSharedSecret({
    required Uint8List sharedSecret,
    required String saltBase64,
    required List<int> info,
  }) async {
    try {
      final salt = base64Decode(saltBase64);

      debugPrint('🔑 Derivando chaves com HKDF:');
      debugPrint('   Shared Secret: ${base64Encode(sharedSecret)}');
      debugPrint('   Salt: $saltBase64');
      debugPrint('   Info: ${utf8.decode(info)}');

      // Usar HKDF-SHA256
      final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 64);

      final keyMaterial = await hkdf.deriveKey(
        secretKey: SecretKey(sharedSecret),
        nonce: salt,
        info: info,
      );

      final keyBytes = await keyMaterial.extractBytes();

      final encryptionKey = Uint8List.fromList(keyBytes.sublist(0, 32));
      final hmacKey = Uint8List.fromList(keyBytes.sublist(32, 64));

      debugPrint('   Chaves derivadas:');
      debugPrint(
          '     ENC (${encryptionKey.length} bytes): ${base64Encode(encryptionKey)}');
      debugPrint(
          '     HMAC (${hmacKey.length} bytes): ${base64Encode(hmacKey)}');

      return {
        'encryption': encryptionKey,
        'hmac': hmacKey,
      };
    } catch (e) {
      debugPrint('❌ Erro ao derivar chaves: $e');
      rethrow;
    }
  }

  Future<Uint8List> _hkdfExtract({
    required Uint8List salt,
    required Uint8List ikm,
  }) async {
    final hmac = Hmac(sha256);
    final secretBox = await hmac.calculateMac(
      ikm,
      secretKey: SecretKey(salt),
    );
    return Uint8List.fromList(secretBox.bytes);
  }

  Future<Uint8List> _hkdfExpand({
    required Uint8List prk,
    required List<int> info,
    required int length,
  }) async {
    final hmac = Hmac(sha256);
    final List<int> okm = [];
    var previous = <int>[];
    var iterations = (length / 32).ceil();

    for (var i = 1; i <= iterations; i++) {
      final input = <int>[];
      if (previous.isNotEmpty) input.addAll(previous);
      input.addAll(info);
      input.add(i);

      final secretBox = await hmac.calculateMac(
        Uint8List.fromList(input),
        secretKey: SecretKey(prk),
      );
      final t = secretBox.bytes;
      okm.addAll(t);
      previous = t;
    }

    return Uint8List.fromList(okm.sublist(0, length));
  }

  // Criptografa uma mensagem para envio
  Future<Map<String, String>> encryptMessage(String plaintext) {
    return _messageCrypto.encryptMessage(plaintext);
  }

  // Descriptografa uma mensagem recebida
  Future<String> decryptMessage(Map<String, String> encryptedMessage) {
    return _messageCrypto.decryptMessage(encryptedMessage);
  }

  // Verifica se a criptografia de mensagens está pronta
  bool get isMessageCryptoReady => _messageCrypto.isReady;

  void setSessionKeys(
      {required Uint8List encryptionKey, required Uint8List hmacKey}) {
    _messageCrypto.setSessionKeys(
      encryptionKey: encryptionKey,
      hmacKey: hmacKey,
    );
  }

  // Limpa as chaves de sessão
  void clearSessionKeys() {
    _messageCrypto.clearSessionKeys();
  }
}
