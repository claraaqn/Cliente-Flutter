import 'dart:developer';

import 'package:cliente/services/socket_service_factory.dart';
import 'package:flutter/foundation.dart';

class AuthProvider with ChangeNotifier {
  late dynamic _socketService;

  AuthProvider() {
    // Usa a factory para criar o serviço apropriado
    _socketService = SocketServiceFactory.createSocketService();
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
      final response = await _socketService.registerUser(username, password);

      _isLoading = false;

      if (response['success'] == true) {
        _errorMessage = '';
        notifyListeners();
        return true;
      } else {
        _errorMessage = response['message'] ?? 'Erro desconhecido no registro';
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

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _socketService.login(username, password);

      _isLoading = false;

      if (response['success'] == true) {
        _isLoggedIn = true;
        _userId = response['user_id'];
        _username = username;
        _errorMessage = '';
        notifyListeners();
        return true;
      } else {
        _errorMessage = response['message'] ?? 'Erro desconhecido no login';
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
