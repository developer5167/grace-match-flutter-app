import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../storage/app_storage.dart';
import '../constants/app_constants.dart';

class SocketService {
  io.Socket? _socket;
  bool _listenersBound = false;

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

  final _callController = StreamController<CallEvent>.broadcast();

  Stream<CallEvent> get callStream => _callController.stream;

  // ── Support.
  //
  // Live delivery for a thread the member already has open. The push
  // notification is still what reaches them when the app is closed; this only
  // saves someone sitting on the screen from backing out and reopening.
  final _supportController = StreamController<SupportEvent>.broadcast();

  Stream<SupportEvent> get supportStream => _supportController.stream;

  bool get isConnected => _socket?.connected == true;

  String get _url => AppConstants.socketUrl.isNotEmpty
      ? AppConstants.socketUrl
      : AppConstants.baseUrl.replaceAll('/api/v1', '');

  /// Opens (or re-opens) a socket with the token currently in storage.
  ///
  /// Must be called after OTP login: `main()` only connects when a token
  /// already existed at process start. socket.io reuses a manager by URL,
  /// so a second connect without `forceNew` would keep the previous (null)
  /// handshake auth.
  Future<void> connect() async {
    final token = await AppStorage.getAccessToken();
    if (token == null) return;

    disconnect();

    _socket = io.io(_url, {
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,
      'auth': {'token': token},
    });

    _bindListeners(_socket!);
  }

  void _bindListeners(io.Socket socket) {
    if (_listenersBound) return;
    _listenersBound = true;

    socket.onConnect((_) {});
    socket.onDisconnect((_) {});

    socket.on('new_message', (data) {
      _messageController.add(Map<String, dynamic>.from(data as Map));
    });

    socket.on('message_delivered', (data) {
      _deliveredController.add(Map<String, dynamic>.from(data as Map));
    });

    socket.on('messages_read', (data) {
      _readReceiptController.add(Map<String, dynamic>.from(data as Map));
    });

    socket.on('user_online', (data) {
      _userStatusController.add({
        ...Map<String, dynamic>.from(data as Map),
        'type': 'online',
      });
    });

    socket.on('user_offline', (data) {
      _userStatusController.add({
        ...Map<String, dynamic>.from(data as Map),
        'type': 'offline',
      });
    });

    _socket?.on('support:message', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _supportController.add(SupportEvent(
        ticketId: map['ticket_id']?.toString() ?? '',
        status: map['status']?.toString(),
      ));
    });

    for (final name in const [
      'call:incoming',
      'call:answered',
      'call:ended',
      'call:cancelled',
      'call:signal',
    ]) {
      socket.on(name, (data) {
        _callController.add(
          CallEvent(name, Map<String, dynamic>.from(data as Map)),
        );
      });
    }
  }

  Future<Map<String, dynamic>> startCall({
    required String conversationId,
    bool isVideo = true,
  }) =>
      _ack('call:start', {'conversation_id': conversationId, 'is_video': isVideo});

  Future<Map<String, dynamic>> answerCall(String callId) =>
      _ack('call:answer', {'call_id': callId});

  Future<Map<String, dynamic>> rejectCall(String callId) =>
      _ack('call:reject', {'call_id': callId});

  Future<Map<String, dynamic>> endCall(String callId) =>
      _ack('call:end', {'call_id': callId});

  void sendSignal(String callId, Map<String, dynamic> signal) {
    _socket?.emit('call:signal', {'call_id': callId, 'signal': signal});
  }

  Future<Map<String, dynamic>> _ack(String event, Map<String, dynamic> payload) {
    final completer = Completer<Map<String, dynamic>>();
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return Future.value({'ok': false, 'error': 'You appear to be offline'});
    }

    socket.emitWithAck(event, payload, ack: (res) {
      if (completer.isCompleted) return;
      completer.complete(
        res is Map ? Map<String, dynamic>.from(res) : {'ok': false, 'error': 'No response'},
      );
    });

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => {'ok': false, 'error': 'The server did not respond'},
    );
  }

  void disconnect() {
    final socket = _socket;
    _socket = null;
    _listenersBound = false;
    if (socket != null) {
      socket.disconnect();
      socket.dispose();
    }
  }

  void dispose() {
    _supportController.close();
    _callController.close();
    _messageController.close();
    _deliveredController.close();
    _readReceiptController.close();
    _userStatusController.close();
    disconnect();
  }
}

class CallEvent {
  final String name;
  final Map<String, dynamic> data;

  const CallEvent(this.name, this.data);

  String? get callId => data['call_id']?.toString();
}

/// A support message arrived on a thread.
///
/// Deliberately carries only the ticket id: the screen refetches rather than
/// trusting a socket payload to be the whole message. One extra request is
/// cheaper than two code paths for building the same thread, which is how the
/// socket version and the HTTP version drift apart.
class SupportEvent {
  final String ticketId;
  final String? status;

  const SupportEvent({required this.ticketId, this.status});
}
