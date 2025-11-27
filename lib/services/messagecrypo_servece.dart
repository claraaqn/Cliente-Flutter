import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

class MessageCryptoService {
  Uint8List? _encryptionKey;
  Uint8List? _hmacKey;

  final _hmac = Hmac(Sha256());

  void setSessionKeys({
    required Uint8List encryptionKey,
    required Uint8List hmacKey,
  }) {
    _encryptionKey = encryptionKey;
    _hmacKey = hmacKey;
  }

  // Criptografa uma mensagem para envio (AES-CBC + HMAC)
  Future<Map<String, String>> encryptMessage(String plaintext) async {
    if (_encryptionKey == null || _hmacKey == null) {
      throw Exception('Chaves de sessão não definidas');
    }

    try {
      debugPrint('🔒 Criptografando mensagem: "$plaintext"');

      // 1. Cifrar a mensagem com AES-256 CBC
      final encryptedData = await _aesCbcEncrypt(plaintext, _encryptionKey!);

      // 2. Criar HMAC da mensagem cifrada
      final hmac = await _computeHmac(encryptedData, _hmacKey!);

      final result = {
        'ciphertext': base64Encode(encryptedData),
        'hmac': base64Encode(hmac),
      };

      debugPrint('✅ Mensagem criptografada com sucesso');
      return result;
    } catch (e) {
      debugPrint('❌ Erro ao criptografar mensagem: $e');
      rethrow;
    }
  }

  // Descriptografa uma mensagem recebida
  Future<String> decryptMessage(Map<String, String> encryptedMessage) async {
    if (_encryptionKey == null || _hmacKey == null) {
      throw Exception('Chaves de sessão não definidas');
    }

    try {
      final ciphertext = base64Decode(encryptedMessage['ciphertext']!);
      final receivedHmac = base64Decode(encryptedMessage['hmac']!);

      // 1. Verificar HMAC antes de descriptografar
      final computedHmac = await _computeHmac(ciphertext, _hmacKey!);

      if (!_compareHmac(receivedHmac, computedHmac)) {
        throw Exception('HMAC inválido - mensagem corrompida ou adulterada');
      }

      // 2. Descriptografar a mensagem
      final plaintext = await _aesCbcDecrypt(ciphertext, _encryptionKey!);

      debugPrint('Mensagem descriptografada: "$plaintext"');
      return plaintext;
    } catch (e) {
      debugPrint('Erro ao descriptografar mensagem: $e');
      rethrow;
    }
  }

  // Cifra a mensagem com AES-256 em modo CBC
  Future<Uint8List> _aesCbcEncrypt(String plaintext, Uint8List key) async {
    try {
      // Gerar IV aleatório
      final iv = _generateRandomIV();

      final aesCbc = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);

      // Criar SecretBox
      final secretBox = await aesCbc.encrypt(
        utf8.encode(plaintext),
        secretKey: SecretKey(key),
        nonce: iv,
      );

      // Apenas IV + ciphertext
      return Uint8List.fromList([...iv, ...secretBox.cipherText]);
    } catch (e) {
      throw Exception('Erro na cifra AES-CBC: $e');
    }
  }

  // Decifra a mensagem com AES-256 CBC
  Future<String> _aesCbcDecrypt(Uint8List encryptedData, Uint8List key) async {
    try {
      // Extrair IV (primeiros 16 bytes) e ciphertext
      final iv = encryptedData.sublist(0, 16);
      final ciphertext = encryptedData.sublist(16);

      final aesCbc = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);

      final secretBox = SecretBox(
        ciphertext,
        nonce: iv,
        mac: Mac.empty,
      );

      // Descriptografar
      final decryptedData = await aesCbc.decrypt(
        secretBox,
        secretKey: SecretKey(key),
      );

      return utf8.decode(decryptedData);
    } catch (e) {
      throw Exception('Erro na decifra AES-CBC: $e');
    }
  }

  // Calcula HMAC-SHA256
  Future<Uint8List> _computeHmac(Uint8List data, Uint8List key) async {
    try {
      final mac = await _hmac.calculateMac(
        data,
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(mac.bytes);
    } catch (e) {
      throw Exception('Erro no cálculo HMAC: $e');
    }
  }

  // Compara dois HMACs de forma segura (time-constant)
  bool _compareHmac(Uint8List hmac1, Uint8List hmac2) {
    if (hmac1.length != hmac2.length) return false;

    int result = 0;
    for (int i = 0; i < hmac1.length; i++) {
      result |= hmac1[i] ^ hmac2[i];
    }
    return result == 0;
  }

  // Gera IV aleatório (16 bytes para AES)
  Uint8List _generateRandomIV() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(16, (i) => random.nextInt(256)),
    );
  }

  // Verifica se as chaves de sessão estão definidas
  bool get isReady => _encryptionKey != null && _hmacKey != null;

  // Limpa as chaves de sessão (para logout)
  void clearSessionKeys() {
    _encryptionKey = null;
    _hmacKey = null;
    debugPrint('🗑️ Chaves de sessão limpas');
  }
}
