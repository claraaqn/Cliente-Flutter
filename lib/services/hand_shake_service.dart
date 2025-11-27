import 'dart:convert';
import 'dart:typed_data';

import 'package:cliente/services/crypto_service.dart';
import 'package:cliente/services/messagecrypo_servece.dart';
import 'package:cliente/services/socket_service.dart';
import 'package:flutter/widgets.dart';

class HandshakeService {
  final SocketService _socketService;
  final CryptoService _cryptoService;

  HandshakeService(this._socketService, this._cryptoService);

  Map<String, Uint8List>? _sessionKeys;
  String? _dhePrivateKey;
  String? _dhePublicKey;
  String? _sessionSalt;

  Future<bool> initiateHandshake() async {
    try {
      // 1. Cliente gera par DHE efêmero
      final dheKeyPair = await _cryptoService.generateDHEKeyPair();
      _dhePrivateKey = dheKeyPair['privateKey'];
      _dhePublicKey = dheKeyPair['publicKey'];

      // 2. Cliente gera salt
      _sessionSalt = _cryptoService.generateSalt();

      // 3. Envia handshake_init para servidor
      final response = await _socketService.sendHandshakeInit(
        dhePublicKey: _dhePublicKey!,
        salt: _sessionSalt!,
      );
      if (!response['success']) {
        return false;
      }

      // 4. Recebe handshake_response do servidor
      final serverPublicKey = response['data']['server_public_key'];
      final sessionId = response['data']['session_id'];

      // 5. Calcula segredo compartilhado
      final sharedSecret = _cryptoService.computeSharedSecretBytes(
        ownPrivateBase64: _dhePrivateKey!,
        peerPublicBase64: serverPublicKey,
      );

      // 6. Deriva chaves de sessão
      _sessionKeys = await _cryptoService.deriveKeysFromSharedSecret(
        sharedSecret: await sharedSecret,
        saltBase64: _sessionSalt!,
        info: utf8.encode('session_keys_v1'),
      );

      _cryptoService.setSessionKeys(
        encryptionKey: sessionKeys!['encryption']!,
        hmacKey: sessionKeys!['hmac']!,
      );

      _socketService.setSessionKeysDirectly(
        sessionId: sessionId,
        encryptionKey: sessionKeys!['encryption']!,
        hmacKey: sessionKeys!['hmac']!,
      );

      debugPrint('✅ Handshake realizado - Chaves de sessão geradas');
      debugPrint('   ENC: ${base64Encode(_sessionKeys!['encryption']!)}');
      debugPrint('   HMAC: ${base64Encode(_sessionKeys!['hmac']!)}');

      debugPrint('✅ Handshake realizado - Chaves de sessão geradas');
      return true;
    } catch (e) {
      debugPrint('❌ Erro no handshake: $e');
      return false;
    }
  }

  Map<String, Uint8List>? get sessionKeys => _sessionKeys;
  String? get sessionSalt => _sessionSalt;
}
