import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  IO.Socket? _socket;
  String? _token;

  /// Called when the server pushes a progress update (cross-device sync).
  void Function(Map<String, dynamic> progress)? onProgressUpdated;

  /// Called when a library item is added, updated, or removed.
  void Function(Map<String, dynamic> data)? onItemUpdated;

  /// Called when a library item is removed.
  void Function(Map<String, dynamic> data)? onItemRemoved;

  /// Called when series data changes.
  void Function()? onSeriesUpdated;

  /// Called when a collection changes.
  void Function()? onCollectionUpdated;

  /// Called when the current user's data changes on the server.
  void Function(Map<String, dynamic> data)? onUserUpdated;

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

      // Cross-device progress sync
      _socket!.on('user_item_progress_updated', (data) {
        if (data is Map<String, dynamic>) {
          final patch = data['data'] as Map<String, dynamic>?;
          if (patch != null) {
            debugPrint('[Socket] Progress updated for ${patch['libraryItemId']}');
            onProgressUpdated?.call(patch);
          }
        }
      });

      // Library item changes
      _socket!.on('item_added', (data) {
        debugPrint('[Socket] Item added');
        if (data is Map<String, dynamic>) onItemUpdated?.call(data);
      });
      _socket!.on('item_updated', (data) {
        debugPrint('[Socket] Item updated');
        if (data is Map<String, dynamic>) onItemUpdated?.call(data);
      });
      _socket!.on('item_removed', (data) {
        debugPrint('[Socket] Item removed');
        if (data is Map<String, dynamic>) onItemRemoved?.call(data);
      });

      // Series changes
      _socket!.on('series_added', (_) {
        debugPrint('[Socket] Series added');
        onSeriesUpdated?.call();
      });
      _socket!.on('series_updated', (_) {
        debugPrint('[Socket] Series updated');
        onSeriesUpdated?.call();
      });
      _socket!.on('series_removed', (_) {
        debugPrint('[Socket] Series removed');
        onSeriesUpdated?.call();
      });

      // Collection changes
      _socket!.on('collection_added', (_) {
        debugPrint('[Socket] Collection added');
        onCollectionUpdated?.call();
      });
      _socket!.on('collection_updated', (_) {
        debugPrint('[Socket] Collection updated');
        onCollectionUpdated?.call();
      });
      _socket!.on('collection_removed', (_) {
        debugPrint('[Socket] Collection removed');
        onCollectionUpdated?.call();
      });

      // Current user updated
      _socket!.on('user_updated', (data) {
        debugPrint('[Socket] User updated');
        if (data is Map<String, dynamic>) onUserUpdated?.call(data);
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
    onProgressUpdated = null;
    onItemUpdated = null;
    onItemRemoved = null;
    onSeriesUpdated = null;
    onCollectionUpdated = null;
    onUserUpdated = null;
  }
}
