import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../storage/app_storage.dart';
import '../constants/app_constants.dart';

class SocketService {
  io.Socket? _socket;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _deliveredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _readReceiptController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _userStatusController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get deliveredStream =>
      _deliveredController.stream;
  Stream<Map<String, dynamic>> get readReceiptStream =>
      _readReceiptController.stream;
  /// Emits `{ user_id, type: 'online'|'offline', last_seen_at? }`
  Stream<Map<String, dynamic>> get userStatusStream =>
      _userStatusController.stream;

  void connect() async {
    final token = await AppStorage.getAccessToken();
    if (token == null) return;

    _socket = io.io(
        AppConstants.socketUrl.isNotEmpty
            ? AppConstants.socketUrl
            : AppConstants.baseUrl.replaceAll('/api/v1', ''),
        {
      'transports': ['websocket'],
      'autoConnect': true,
      'auth': {'token': token},
    });

    _socket?.onConnect((_) => print('📡 Socket Connected'));
    _socket?.onDisconnect((_) => print('📡 Socket Disconnected'));

    _socket?.on('new_message', (data) {
      _messageController.add(Map<String, dynamic>.from(data as Map));
    });

    _socket?.on('message_delivered', (data) {
      _deliveredController.add(Map<String, dynamic>.from(data as Map));
    });

    _socket?.on('messages_read', (data) {
      _readReceiptController.add(Map<String, dynamic>.from(data as Map));
    });

    _socket?.on('user_online', (data) {
      _userStatusController.add({
        ...Map<String, dynamic>.from(data as Map),
        'type': 'online',
      });
    });

    _socket?.on('user_offline', (data) {
      _userStatusController.add({
        ...Map<String, dynamic>.from(data as Map),
        'type': 'offline',
      });
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void dispose() {
    _messageController.close();
    _deliveredController.close();
    _readReceiptController.close();
    _userStatusController.close();
    disconnect();
  }
}
