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
      // Gera chaves ECC
      final keyPair = await _cryptoService.generateKeyPair();
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;

      final testKeyPair =
          await _cryptoService.generateKeyPairFromPrivate(privateKey);
      final derivedPublicKey = testKeyPair['publicKey']!;

      if (publicKey != derivedPublicKey) {
        _errorMessage = 'Erro: Chaves não correspondem';
        debugPrint('ERRO: As chaves pública e privada não correspondem!');
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

        _errorMessage = '';
        notifyListeners();
        return true;
      } else {
        _errorMessage = response['message'] ?? 'Erro no registro';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Erro de conexão: $e';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final handshakeSuccess = await _handshakeService.initiateHandshake();
      if (!handshakeSuccess) {
        _errorMessage = 'Falha no handshake';
        return false;
      }

      final sessionKeys = _handshakeService.sessionKeys;
      if (sessionKeys == null) {
        _errorMessage = 'Chaves de sessão não disponíveis';
        return false;
      }

      final response = await _socketService.login(
        username: username,
        password: password,
      );

      _isLoading = false;

      if (response['success'] == true) {
        final userData = response['data']?['user_data'] ?? response['data'];

        if (userData != null) {
          _isLoggedIn = true;
          _userId = int.tryParse(userData['user_id']?.toString() ?? '');
          _username = userData['username']?.toString() ?? username;

          final privateKey = await _localStorageService.getPrivateKey();
          if (privateKey != null) {
            await _localStorageService.saveUserCredentials(
                username, privateKey);
          }

          _errorMessage = '';
          notifyListeners();
          return true;
        } else {
          _errorMessage = 'Dados do usuário não encontrados';
          notifyListeners();
          return false;
        }
      } else {
        _errorMessage = response['message'] ?? 'Erro no login';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Erro de conexão: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _initializeAutoLogin() async {
    try {
      // Verificar se há credenciais salvas
      final hasCredentials = await _localStorageService.hasCredentials();

      if (hasCredentials) {
        final credentials = await _localStorageService.getUserCredentials();
        if (credentials != null) {
          final username = credentials['username']!;
          debugPrint('Usuário das credenciais: $username');
          await _tryAutoLogin();
        }
      } else {
        debugPrint('Nenhuma credencial salva para autenticação automática');
        _isAutoLoggingIn = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro na inicialização automática: $e');
      _isAutoLoggingIn = false;
      notifyListeners();
    }
  }

  Future<void> _tryAutoLogin() async {
    _isAutoLoggingIn = true;
    notifyListeners();

    try {
      // 1. Conectar ao servidor
      final connected = await _socketService.connect();
      if (!connected) {
        throw Exception('Falha na conexão com o servidor');
      }

      // 2. Obter credenciais salvas
      final credentials = await _localStorageService.getUserCredentials();
      if (credentials == null) {
        throw Exception('Credenciais não encontradas');
      }

      final username = credentials['username']!;

      // 3. Tentar autenticação por desafio
      final success = await loginWithChallenge(username);

      if (success) {
        debugPrint('Autenticação automática bem-sucedida!');
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        throw Exception('Autenticação por desafio falhou');
      }
    } catch (e) {
      debugPrint('Autenticação automática falhou: $e');
      _errorMessage = 'Autenticação automática falhou: $e';
    } finally {
      _isAutoLoggingIn = false;
      notifyListeners();
    }
  }

  Future<bool> loginWithChallenge(String username) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // 1. Primeiro, realizar handshake para criptografia
      final handshakeSuccess = await _handshakeService.initiateHandshake();
      if (!handshakeSuccess) {
        _errorMessage = 'Falha no handshake de criptografia';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. Iniciar desafio com o servidor
      final challengeResponse = await _initiateChallenge(username);
      if (!challengeResponse['success']) {
        _errorMessage = challengeResponse['message'] ?? 'Erro no desafio';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final nonceB64 = challengeResponse['data']['nonce'];

      // 3. Assinar o nonce com a chave privada local
      final signature = await _signChallenge(nonceB64);
      if (signature == null) {
        _errorMessage = 'Erro ao assinar desafio';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 4. Verificar assinatura com o servidor
      final verifyResponse = await _verifyChallenge(username, signature);
      if (!verifyResponse['success']) {
        _errorMessage = verifyResponse['message'] ?? 'Autenticação falhou';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 5. Autenticação bem-sucedida
      final userData = verifyResponse['data']['user_data'];
      _isLoggedIn = true;
      _userId = _parseUserId(userData['user_id']);
      _username = userData['username']?.toString() ?? username;

      _errorMessage = '';
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
      _errorMessage = 'Erro na autenticação: $e';
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
      final credentials = await _localStorageService.getUserCredentials();
      if (credentials == null) {
        debugPrint('Credenciais não encontradas localmente');
        return null;
      }

      final privateKey = credentials['privateKey']!;

      // Decodificar nonce
      final nonce = base64Decode(nonceB64);

      // Assinar o nonce com Ed25519
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

  void logout() {
    _isLoggedIn = false;
    _userId = null;
    _username = null;
    _socketService.disconnect();
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
        // Tenta converter string para int
        return int.tryParse(userIdValue);
      }
      if (userIdValue is double) {
        return userIdValue.toInt();
      }
      // Tenta converter para string e depois para int
      return int.tryParse(userIdValue.toString());
    } catch (e) {
      debugPrint('Erro ao parser userId: $e, valor: $userIdValue');
      return null;
    }
  }
}
