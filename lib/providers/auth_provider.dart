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

  AuthProvider()
      : _localStorageService = LocalStorageService() {
    // ← Inicializa aqui
    _socketService = SocketServiceFactory.createSocketService();
    _handshakeService = HandshakeService(_socketService, _cryptoService);
    log('✅ AuthProvider inicializado com: ${_socketService.runtimeType}');
  }

  bool _isLoading = false;
  String _errorMessage = '';
  bool _isLoggedIn = false;
  int? _userId;
  String? _username;

  bool get isLoading => _isLoading;
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

      final response = await _socketService.register(
        username: username,
        password: password,
        publicKey: publicKey,
      );

      if (response['success'] == true) {
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
}
