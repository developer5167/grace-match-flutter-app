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

  // ── Calling.
  //
  // Signalling only. The SDP and ICE payloads are opaque here; they are handed
  // straight to the peer connection. Nothing about the call's rules lives on
  // this side — the server decides who may ring whom.
  final _callController = StreamController<CallEvent>.broadcast();

  /// Incoming call, answered, ended, cancelled, and WebRTC signal frames.
  Stream<CallEvent> get callStream => _callController.stream;

  bool get isConnected => _socket?.connected == true;

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

    for (final name in const [
      'call:incoming',
      'call:answered',
      'call:ended',
      'call:cancelled',
      'call:signal',
    ]) {
      _socket?.on(name, (data) {
        _callController.add(
          CallEvent(name, Map<String, dynamic>.from(data as Map)),
        );
      });
    }
  }

  /// Ring the other member of a conversation.
  ///
  /// Resolves to the server's acknowledgement: either the new call id and the
  /// ICE servers to use, or the reason it was refused.
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

  /// Forward one WebRTC frame. Fire and forget — the peer connection retries
  /// on its own, and an ack per ICE candidate would be a lot of round trips.
  void sendSignal(String callId, Map<String, dynamic> signal) {
    _socket?.emit('call:signal', {'call_id': callId, 'signal': signal});
  }

  /// Emit with acknowledgement, and a deadline.
  ///
  /// Without the timeout a dropped connection leaves the caller's UI waiting
  /// on a dialogue that will never resolve.
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
    _socket?.disconnect();
    _socket = null;
  }

  void dispose() {
    _callController.close();
    _messageController.close();
    _deliveredController.close();
    _readReceiptController.close();
    _userStatusController.close();
    disconnect();
  }
}


/// One signalling event from the server.
class CallEvent {
  final String name;
  final Map<String, dynamic> data;

  const CallEvent(this.name, this.data);

  String? get callId => data['call_id']?.toString();
}
