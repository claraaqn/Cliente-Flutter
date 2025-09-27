// services/socket_service_factory.dart
import 'dart:developer' as console;

import 'package:cliente/services/socket_service.dart';
import 'package:cliente/services/web_socket_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class SocketServiceFactory {
  static dynamic createSocketService() {
    if (kIsWeb) {
      // Para navegador (Chrome)
      console.log('🌐 Usando WebSocketService para web');
      return WebSocketService();
    } else {
      // Para emulador/dispositivo móvel
      console.log('📱 Usando SocketService para mobile');
      return SocketService();
    }
  }
}
