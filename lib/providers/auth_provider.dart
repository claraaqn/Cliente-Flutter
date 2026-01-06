import 'dart:convert';
import 'dart:developer';
import 'package:cliente/services/hand_shake_service.dart';
import 'package:cliente/services/local_storage_service.dart';
import 'package:cliente/services/socket_service_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:cliente/services/crypto_service.dart';

class AuthProvider with ChangeNotifier {
  late dynamic _socketService;
  final CryptoService _cryptoService = CryptoService();
  final LocalStorageService _localStorageService;
  late final HandshakeService _handshakeService;

  AuthProvider() : _localStorageService = LocalStorageService() {
    _socketService = SocketServiceFactory.createSocketService();
    _handshakeService = HandshakeService(_socketService, _cryptoService);

    _socketService.setHandshakeService(_handshakeService);

    log('AuthProvider inicializado com: ${_socketService.runtimeType}');

    _initializeAutoLogin();
  }

  bool _isLoading = false;
  bool _isAutoLoggingIn = false;
  String _errorMessage = '';
  bool _isLoggedIn = false;
  int? _userId;
  String? _username;

  VoidCallback? _onAuthenticationComplete;

  bool get isLoading => _isLoading;
  bool get isAutoLoggingIn => _isAutoLoggingIn;
  String get errorMessage => _errorMessage;
  bool get isLoggedIn => _isLoggedIn;
  int? get userId => _userId;
  String? get username => _username;
  dynamic get socketService => _socketService;

  Future<void> sendMessage(String receiver, String content) async {
    await _socketService.sendMessage(receiver, content);
  }

  Future<void> initialize() async {
    try {
      await _socketService.connect();
    } catch (e) {
      _errorMessage = 'Erro ao conectar com servidor';
      notifyListeners();
    }
  }

  Future<bool> register(String username, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final keyPair = await _cryptoService.generateKeyPair();
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;

      final testKeyPair =
          await _cryptoService.generateKeyPairFromPrivate(privateKey);
      final derivedPublicKey = testKeyPair['publicKey']!;

      if (publicKey != derivedPublicKey) {
        debugPrint('Erro: Chaves não correspondem');
        return false;
      }

      final response = await _socketService.register(
        username: username,
        password: password,
        publicKey: publicKey,
      );

      if (response['success'] == true) {
        await _localStorageService.saveUserCredentials(username, privateKey);
        await _localStorageService.savePrivateKey(privateKey);

        notifyListeners();
        return true;
      } else {
        _errorMessage = response['message'] ?? 'Erro no registro';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
     debugPrint('Erro de conexão: $e');
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final handshakeSuccess = await _handshakeService.initiateHandshake();
      if (!handshakeSuccess) {
       debugPrint('Falha no handshake');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final response = await _socketService.login(
        username: username,
        password: password,
      );

      if (response['success'] == true) {
        final userData = response['data']?['user_data'] ?? response['data'];
        if (userData != null) {
          _userId = int.tryParse(userData['user_id']?.toString() ?? '');
          _username = userData['username'] ?? username;

          if (_userId != null) {
            await _localStorageService.initForUser(_userId!);

            String? privateKey = await _localStorageService.getPrivateKey();

            if (privateKey == null || privateKey.length < 30) {
              debugPrint(
                  "Novo dispositivo detectado ou chave perdida. Gerando novas chaves...");

              final newKeyPair = await _cryptoService.generateKeyPair();
              final newPublicKey = newKeyPair['publicKey']!;
              final newPrivateKey = newKeyPair['privateKey']!;

              final updateResponse = await _socketService.loginAsNewDevice(
                username: username,
                password: password,
                newPublicKey: newPublicKey,
              );

              if (updateResponse['success'] == true) {
                privateKey = newPrivateKey;
                await _localStorageService.savePrivateKey(newPrivateKey);
                debugPrint(
                    "Novas chaves geradas e sincronizadas com o servidor.");
              } else {
               debugPrint("Falha ao registrar novo dispositivo.");
                _isLoading = false;
                notifyListeners();
                return false;
              }
            }

            await _localStorageService.saveUserCredentials(
                _username!, privateKey);
            _isLoggedIn = true;
          }

          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      _errorMessage = response['message'] ?? 'Erro no login';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Erro de conexão: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _initializeAutoLogin() async {
    try {
      final credentials = await _localStorageService.getUserCredentials();
      final privateKey = await _localStorageService.getPrivateKey();

      if (credentials != null && privateKey != null && privateKey.length > 30) {
        final username = credentials['username']!;
        debugPrint('Tentando autologin para: $username');
        await _tryAutoLogin();
      } else {
        debugPrint(
            'Nenhuma chave válida para autologin. Aguardando login manual.');
        _isAutoLoggingIn = false;
        notifyListeners();
      }
    } catch (e) {
      _isAutoLoggingIn = false;
      notifyListeners();
    }
  }

  Future<void> _tryAutoLogin() async {
    _isAutoLoggingIn = true;
    notifyListeners();

    try {
      final connected = await _socketService.connect();
      if (!connected) {
        throw Exception('Falha na conexão com o servidor');
      }

      final credentials = await _localStorageService.getUserCredentials();
      if (credentials == null) {
        throw Exception('Credenciais não encontradas');
      }

      final username = credentials['username']!;

      final success = await loginWithChallenge(username);

      if (success) {
        debugPrint('Autenticação automática bem-sucedida!');

        if (_userId != null) {
          await _localStorageService.initForUser(_userId!);
        }

        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        throw Exception('Autenticação por desafio falhou');
      }
    } catch (e) {
      debugPrint('Autenticação automática falhou: $e');
    } finally {
      _isAutoLoggingIn = false;
      notifyListeners();
    }
  }

  Future<bool> loginWithChallenge(String username) async {
    _isLoading = true;
    notifyListeners();

    try {
      final handshakeSuccess = await _handshakeService.initiateHandshake();
      if (!handshakeSuccess) {
       debugPrint('Falha no handshake de criptografia');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final challengeResponse = await _initiateChallenge(username);
      if (!challengeResponse['success']) {
        debugPrint(challengeResponse['message'] ?? 'Erro no desafio');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final nonceB64 = challengeResponse['data']['nonce'];

      final signature = await _signChallenge(nonceB64);
      if (signature == null) {
        debugPrint('Erro ao assinar desafio');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final verifyResponse = await _verifyChallenge(username, signature);
      if (!verifyResponse['success']) {
        debugPrint(verifyResponse['message'] ?? 'Autenticação falhou');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final userData = verifyResponse['data']['user_data'];
      _isLoggedIn = true;
      _userId = _parseUserId(userData['user_id']);
      _username = userData['username']?.toString() ?? username;

      if (_userId != null) {
        await _localStorageService.initForUser(_userId!);
      } else {
        debugPrint('Erro crítico: UserId é nulo após login!');
      }

      _isLoading = false;
      notifyListeners();

      if (_onAuthenticationComplete != null) {
        _onAuthenticationComplete!();
      }

      _socketService.setAuthenticatedUser(
        userId: _userId!,
        username: _username!,
      );

      debugPrint('Autenticação por desafio bem-sucedida');
      return true;
    } catch (e) {
      _isLoading = false;
      debugPrint('Erro na autenticação: $e');
      notifyListeners();
      return false;
    }
  }

  void setOnAuthenticationComplete(VoidCallback callback) {
    _onAuthenticationComplete = callback;
  }

  Future<Map<String, dynamic>> _initiateChallenge(String username) async {
    try {
      final response = await _socketService.sendAndWaitForResponse(
        {
          'action': 'initiate_challenge',
          'username': username,
        },
        'initiate_challenge_response',
      );

      return response;
    } catch (e) {
      debugPrint('Erro ao iniciar desafio: $e');
      return {'success': false, 'message': 'Erro de conexão'};
    }
  }

  Future<String?> _signChallenge(String nonceB64) async {
    try {
      var privateKey = await _localStorageService.getPrivateKey();

      if (privateKey == null ||
          privateKey.isEmpty ||
          privateKey == "session_active") {
        final credentials = await _localStorageService.getUserCredentials();
        privateKey = credentials?['privateKey'];
      }

      if (privateKey == null ||
          privateKey.length < 32 ||
          privateKey == "session_active") {
        debugPrint('Chave privada inválida ou ausente para autologin');
        return null;
      }

      final nonce = base64Decode(nonceB64);
      final signature = await _cryptoService.signData(nonce, privateKey);

      debugPrint('Nonce assinado com sucesso');
      return signature;
    } catch (e) {
      debugPrint('Erro ao assinar desafio: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _verifyChallenge(
      String username, String signature) async {
    try {
      final response = await _socketService.sendAndWaitForResponse(
        {
          'action': 'verify_challenge',
          'username': username,
          'signature': signature,
        },
        'verify_challenge_response',
      );

      return response;
    } catch (e) {
      debugPrint('Erro ao verificar desafio: $e');
      return {'success': false, 'message': 'Erro de conexão'};
    }
  }

  Future<bool> hasLocalCredentials(String username) async {
    try {
      final privateKey = await _localStorageService.getPrivateKey();
      return privateKey != null;
    } catch (e) {
      debugPrint('Erro ao verificar credenciais locais: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _userId = null;
    _username = null;
    _localStorageService.clearUserCredentials();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _socketService.disconnect();
    super.dispose();
  }

  int? _parseUserId(dynamic userIdValue) {
    if (userIdValue == null) return null;

    try {
      if (userIdValue is int) return userIdValue;
      if (userIdValue is String) {
        return int.tryParse(userIdValue);
      }
      if (userIdValue is double) {
        return userIdValue.toInt();
      }
      return int.tryParse(userIdValue.toString());
    } catch (e) {
      debugPrint('Erro ao parser userId: $e, valor: $userIdValue');
      return null;
    }
  }
}
