import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';

class MessageCryptoService {
  Uint8List? _encryptionKey;
  Uint8List? _hmacKey;

  void setSessionKeys({
    required Uint8List encryptionKey,
    required Uint8List hmacKey,
  }) {
    _encryptionKey = encryptionKey;
    _hmacKey = hmacKey;
  }

  // Criptografa uma mensagem para envio (AES-CBC + HMAC)
  Map<String, String> encryptMessage(String plaintext) {
    if (_encryptionKey == null || _hmacKey == null) {
      throw Exception('Chaves de sessão não definidas');
    }

    try {
      debugPrint('🔒 Criptografando mensagem: "$plaintext"');

      // 1. Cifrar a mensagem com AES-256 CBC
      final encryptedData = _aesCbcEncrypt(plaintext, _encryptionKey!);

      // 2. Criar HMAC da mensagem cifrada
      final hmac = _computeHmac(encryptedData, _hmacKey!);

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

  /// Descriptografa uma mensagem recebida
  String decryptMessage(Map<String, String> encryptedMessage) {
    if (_encryptionKey == null || _hmacKey == null) {
      throw Exception('Chaves de sessão não definidas');
    }

    try {
      debugPrint('🔓 Descriptografando mensagem...');

      final ciphertext = base64Decode(encryptedMessage['ciphertext']!);
      final receivedHmac = base64Decode(encryptedMessage['hmac']!);

      // 1. Verificar HMAC antes de descriptografar
      final computedHmac = _computeHmac(ciphertext, _hmacKey!);

      if (!_compareHmac(receivedHmac, computedHmac)) {
        throw Exception('HMAC inválido - mensagem corrompida ou adulterada');
      }

      // 2. Descriptografar a mensagem
      final plaintext = _aesCbcDecrypt(ciphertext, _encryptionKey!);

      debugPrint('✅ Mensagem descriptografada: "$plaintext"');
      return plaintext;
    } catch (e) {
      debugPrint('❌ Erro ao descriptografar mensagem: $e');
      rethrow;
    }
  }

  /// Cifra a mensagem com AES-256 em modo CBC
  Uint8List _aesCbcEncrypt(String plaintext, Uint8List key) {
    try {
      // Gerar IV aleatório
      final iv = _generateRandomIV();

      // Criar cifrador AES-CBC
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
      );

      // Criptografar (a biblioteca já aplica padding PKCS7)
      final encrypted = encrypter.encrypt(plaintext, iv: encrypt.IV(iv));

      // Combinar IV + ciphertext
      return Uint8List.fromList([...iv, ...encrypted.bytes]);
    } catch (e) {
      throw Exception('Erro na cifra AES-CBC: $e');
    }
  }

  // Decifra a mensagem com AES-256 CBC
  String _aesCbcDecrypt(Uint8List encryptedData, Uint8List key) {
    try {
      // Extrair IV (primeiros 16 bytes) e ciphertext
      final iv = encryptedData.sublist(0, 16);
      final ciphertext = encryptedData.sublist(16);

      // Criar decifrador AES-CBC
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
      );

      // Descriptografar (a biblioteca remove padding PKCS7)
      return encrypter.decrypt(
        encrypt.Encrypted(ciphertext),
        iv: encrypt.IV(iv),
      );
    } catch (e) {
      throw Exception('Erro na decifra AES-CBC: $e');
    }
  }

  // Calcula HMAC-SHA256
  Uint8List _computeHmac(Uint8List data, Uint8List key) {
    try {
      final hmac = Hmac(sha256, key);
      final digest = hmac.convert(data);
      return Uint8List.fromList(digest.bytes);
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
