import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../storage/app_storage.dart';
import '../constants/app_constants.dart';
import 'dio_client.dart';

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

  /// `{ conversation_id, user_id, typing }` from the other person in a chat.
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;

  /// Tell the other person this member is (or has stopped) typing. The
  /// server turns a start into their "is typing…" indicator and, if they are
  /// not in the chat and want it, a notification.
  void sendTyping(String conversationId, {required bool typing}) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emit('typing', {'conversation_id': conversationId, 'typing': typing});
  }

  String? _viewingChat;

  /// So the server can skip a push for a chat this member is already looking at.
  void setViewingChat(String? conversationId) {
    _viewingChat = conversationId;
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emit(conversationId == null ? 'chat:close' : 'chat:open', {
      'conversation_id': conversationId,
    });
  }

  Stream<CallEvent> get callStream => _callController.stream;

  // ── Support.
  //
  // Live delivery for a thread the member already has open. The push
  // notification is still what reaches them when the app is closed; this only
  // saves someone sitting on the screen from backing out and reopening.
  final _supportController = StreamController<SupportEvent>.broadcast();

  Stream<SupportEvent> get supportStream => _supportController.stream;

  bool get isConnected => _socket?.connected == true;

  /// The call this phone is in, reported on every connect so the server can
  /// finish calls the app is no longer part of.
  String? Function()? activeCallId;

  Future<bool>? _ensuring;

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

    final socket = io.io(_url, {
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 20,
      'reconnectionDelay': 400,
      'reconnectionDelayMax': 4000,
      'timeout': 10000,
      // Read on every handshake, reconnects included. A token captured once
      // here expires after fifteen minutes, and every reconnect after that is
      // refused until something else happens to refresh it — "You appear to
      // be offline" on a phone that is plainly online.
      'auth': (void Function(Map) send) {
        DioClient.freshAccessToken().then(
          (t) => send({'token': t ?? ''}),
          onError: (_) => send({'token': ''}),
        );
      },
    });
    _socket = socket;

    _bindListeners(socket);
  }

  DateTime? _lastAuthRetry;

  /// The server refused the handshake. socket.io does not retry that on its
  /// own, so refresh the token once and open a new connection.
  Future<void> _onAuthRejected() async {
    final last = _lastAuthRetry;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastAuthRetry = DateTime.now();
    try {
      await DioClient.refreshTokens();
    } catch (_) {
      return;
    }
    await connect();
  }

  /// Razorpay (and any other native overlay) pauses the app and drops the
  /// websocket. A full restart used to be the only way back online. Resume
  /// and the next call both come through here.
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 6),
  }) {
    if (isConnected) return Future.value(true);
    return _ensuring ??= _ensureConnected(timeout).whenComplete(() {
      _ensuring = null;
    });
  }

  Future<bool> _ensureConnected(Duration timeout) async {
    final token = await AppStorage.getAccessToken();
    if (token == null) return false;

    if (_socket != null && !isConnected) {
      _socket!.connect();
      if (await _waitUntilConnected(timeout)) return true;
    }

    if (!isConnected) {
      await connect();
      if (await _waitUntilConnected(timeout)) return true;
    }

    return isConnected;
  }

  Future<bool> _waitUntilConnected(Duration timeout) async {
    if (isConnected) return true;
    final socket = _socket;
    if (socket == null) return false;

    final completer = Completer<bool>();
    void onConnect(_) {
      if (!completer.isCompleted) completer.complete(true);
    }

    socket.on('connect', onConnect);
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => isConnected,
      );
    } finally {
      socket.off('connect', onConnect);
    }
  }

  void _bindListeners(io.Socket socket) {
    if (_listenersBound) return;
    _listenersBound = true;

    socket.onConnect((_) {
      socket.emit('call:sync', {'active_call_id': activeCallId?.call()});
      final viewing = _viewingChat;
      if (viewing != null) socket.emit('chat:open', {'conversation_id': viewing});
    });
    socket.onDisconnect((_) {});
    socket.onConnectError((err) {
      final text = err is Map ? err['message']?.toString() : err?.toString();
      if (text != null && text.contains('Authentication error')) {
        if (text.contains('suspended') || text.contains('deactivated')) return;
        _onAuthRejected();
      }
    });

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

    socket.on('typing', (data) {
      if (data is Map) _typingController.add(Map<String, dynamic>.from(data));
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
      _ack('call:start', {'conversation_id': conversationId, 'is_video': isVideo},
          connectWithin: const Duration(seconds: 10));

  /// Generous on purpose: answering from the lock screen cold-starts the app,
  /// and the socket is still opening when the member taps Accept.
  Future<Map<String, dynamic>> answerCall(String callId) =>
      _ack('call:answer', {'call_id': callId}, connectWithin: const Duration(seconds: 15));

  Future<Map<String, dynamic>> rejectCall(String callId) =>
      _ack('call:reject', {'call_id': callId});

  Future<Map<String, dynamic>> endCall(String callId) =>
      _ack('call:end', {'call_id': callId});

  void sendSignal(String callId, Map<String, dynamic> signal) {
    _socket?.emit('call:signal', {'call_id': callId, 'signal': signal});
  }

  Future<Map<String, dynamic>> _ack(
    String event,
    Map<String, dynamic> payload, {
    Duration connectWithin = const Duration(seconds: 6),
  }) async {
    final ready = await ensureConnected(timeout: connectWithin);
    final socket = _socket;
    if (!ready || socket == null || !socket.connected) {
      return {
        'ok': false,
        'error': 'Could not reach GraceMatch. Check your connection and try again.',
        'code': 'OFFLINE',
      };
    }

    final completer = Completer<Map<String, dynamic>>();
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
    _typingController.close();
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
