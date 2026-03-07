import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  IO.Socket? _socket;
  String? _token;

  void connect(String serverUrl, String token) {
    if (_socket != null) disconnect();

    _token = token;

    try {
      _socket = IO.io(serverUrl, IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .build());

      // onConnect fires on initial connect AND every reconnect
      _socket!.onConnect((_) {
        debugPrint('[Socket] Connected, sending auth');
        _socket!.emit('auth', _token);
      });

      _socket!.on('init', (_) {
        debugPrint('[Socket] Authenticated - user is online');
      });

      _socket!.on('auth_failed', (_) {
        debugPrint('[Socket] Auth failed');
        disconnect();
      });

      _socket!.onDisconnect((_) {
        debugPrint('[Socket] Disconnected');
      });

      _socket!.onConnectError((err) {
        debugPrint('[Socket] Connect error: $err');
      });
    } catch (e) {
      debugPrint('[Socket] Failed to connect: $e');
      _socket = null;
      _token = null;
    }
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _token = null;
  }
}
