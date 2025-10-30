import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:crypto/crypto.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  // Gera um par de chaves ECC
  Map<String, String> generateKeyPair() {
    final ecParams = ECDomainParameters('secp256k1');
    final keyGenerator = ECKeyGenerator();
    final keyParams = ECKeyGeneratorParameters(ecParams);

    keyGenerator.init(ParametersWithRandom(
      keyParams,
      FortunaRandom()..seed(KeyParameter(_getSecureRandom())),
    ));

    final keyPair = keyGenerator.generateKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    return {
      'privateKey': _encodePrivateKey(privateKey),
      'publicKey': _encodePublicKey(publicKey),
    };
  }

  Uint8List _getSecureRandom() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  String _encodePrivateKey(ECPrivateKey privateKey) {
    // Converte BigInt para bytes (32 bytes para secp256k1)
    final d = privateKey.d!;
    final bytes = _bigIntToBytes(d, 32);
    return base64Encode(bytes);
  }

  String _encodePublicKey(ECPublicKey publicKey) {
    final q = publicKey.Q!;

    // Converte coordenadas x e y para bytes
    final xBytes = _bigIntToBytes(q.x!.toBigInteger()!, 32);
    final yBytes = _bigIntToBytes(q.y!.toBigInteger()!, 32);

    // Formato comprimido: 0x02 (par) ou 0x03 (ímpar) + coordenada x
    final header = yBytes[31] % 2 == 0 ? 0x02 : 0x03;
    final publicKeyBytes = Uint8List.fromList([header] + xBytes.toList());

    return base64Encode(publicKeyBytes);
  }

  Uint8List _bigIntToBytes(BigInt number, int length) {
    var hex = number.toRadixString(16);
    // Preenche com zeros à esquerda se necessário
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    if (hex.length ~/ 2 < length) {
      hex = hex.padLeft(length * 2, '0');
    }

    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      final byteStr = hex.substring(i * 2, i * 2 + 2);
      result[length - 1 - i] = int.parse(byteStr, radix: 16);
    }

    return result;
  }

  String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Encode(bytes);
  }

  //TODO: assinatura e verificação
  String signMessage(String message, String privateKeyBase64) {
    // Implementação de assinatura ECDSA
    final messageBytes = utf8.encode(message);
    final digest = sha256.convert(messageBytes).bytes;
    // TODO: Implementar assinatura ECDSA com a chave privada
    return base64Encode(digest);
  }

  bool verifySignature(
      String message, String signature, String publicKeyBase64) {
    // Implementação de verificação ECDSA
    final messageBytes = utf8.encode(message);
    final digest = sha256.convert(messageBytes).bytes;
    // TODO: Implementar verificação ECDSA com a chave pública
    return true;
  }
}
