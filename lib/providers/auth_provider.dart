import 'package:flutter/foundation.dart';
import 'package:cliente/services/socket_service.dart';

class AuthProvider with ChangeNotifier {
  final SocketService _socketService = SocketService();
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
  SocketService get socketService => _socketService;

  Future<void> initialize() async {
    try {
      await _socketService.connect();
    } catch (e) {
      _setErrorMessage('Erro ao conectar com servidor');
    }
  }

  Future<bool> register(String username, String password) async {
    _setLoading(true);
    _setErrorMessage('');

    try {
      final response = await _socketService.registerUser(username, password);

      _setLoading(false);

      if (response['success'] == true) {
        _setErrorMessage('');
        return true;
      } else {
        _setErrorMessage(
            response['message'] ?? 'Erro desconhecido no registro');
        return false;
      }
    } catch (e) {
      _setLoading(false);
      _setErrorMessage('Erro de conexão: $e');
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    _setLoading(true);
    _setErrorMessage('');

    try {
      final response = await _socketService.login(username, password);

      _setLoading(false);

      if (response['success'] == true) {
        _setLoggedIn(true, response['user_id'], username);
        _setErrorMessage('');
        return true;
      } else {
        _setErrorMessage(response['message'] ?? 'Erro desconhecido no login');
        return false;
      }
    } catch (e) {
      _setLoading(false);
      _setErrorMessage('Erro de conexão: $e');
      return false;
    }
  }

  void logout() {
    _setLoggedIn(false, null, null);
    _socketService.disconnect();
  }

  void clearError() {
    _setErrorMessage('');
  }

  // Métodos privados para evitar múltiplos notifyListeners()
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setErrorMessage(String message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      notifyListeners();
    }
  }

  void _setLoggedIn(bool loggedIn, int? userId, String? username) {
    if (_isLoggedIn != loggedIn || _userId != userId || _username != username) {
      _isLoggedIn = loggedIn;
      _userId = userId;
      _username = username;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _socketService.disconnect();
    super.dispose();
  }
}
