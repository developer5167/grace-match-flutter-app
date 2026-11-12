import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'chat_event.dart';
import 'chat_state.dart';
import '../data/chat_repository.dart';
import '../../../core/network/socket_service.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _repository;
  final SocketService _socketService;

  String? _currentConversationId;
  Object? _currentOwner;
  // Keep latest conversation list so we can update previews/unread counts
  // even while the state is MessagesLoaded (inside a chat screen).
  List<Map<String, dynamic>> _conversationCache = [];

  // Track IDs of messages we sent via HTTP so we don't double-add them
  // if the backend ever echoes them back through the socket.
  final Set<String> _sentMessageIds = {};

  // Delivered receipts that arrived before the HTTP response came back
  // (socket is faster than HTTP round-trip). Flushed when HTTP confirms.
  final Set<String> _pendingDelivered = {};

  // Which conversation the current MessagesLoaded belongs to, and which
  // fetches are out, so an open chat is not blanked or fetched twice.
  String? _messagesConversationId;
  final Set<String> _fetchingMessages = {};
  bool _fetchingConversations = false;
  // Asked for again while a fetch was out: run once more after it, so a
  // refresh after closing a chat is not answered by an older request.
  bool _conversationsAskedAgain = false;

  // markRead is sent at most once a second per conversation while messages
  // stream in: the first straight away, the rest folded into one trailing
  // call.
  final Map<String, DateTime> _lastMarkRead = {};
  final Map<String, Timer> _pendingMarkRead = {};

  StreamSubscription? _socketSubscription;
  StreamSubscription? _deliveredSubscription;
  StreamSubscription? _readSubscription;

  ChatBloc(this._repository, this._socketService) : super(ChatInitial()) {
    on<FetchConversationsEvent>(_onFetchConversations);
    on<FetchMessagesEvent>(_onFetchMessages);
    on<SetCurrentConversationEvent>(_onSetCurrentConversation);
    on<SendMessageEvent>(_onSendMessage);
    on<NewMessageReceivedEvent>(_onNewMessageReceived);
    on<MessageDeliveredEvent>(_onMessageDelivered);
    on<MessagesReadEvent>(_onMessagesRead);

    _socketSubscription = _socketService.messageStream.listen((msg) {
      add(NewMessageReceivedEvent(msg));
    });

    _deliveredSubscription = _socketService.deliveredStream.listen((data) {
      add(
        MessageDeliveredEvent(
          messageId: data['message_id']?.toString() ?? '',
          conversationId: data['conversation_id']?.toString() ?? '',
        ),
      );
    });

    _readSubscription = _socketService.readReceiptStream.listen((data) {
      final ids = List<String>.from(
        (data['message_ids'] as List? ?? []).map((e) => e.toString()),
      );
      add(
        MessagesReadEvent(
          messageIds: ids,
          conversationId: data['conversation_id']?.toString() ?? '',
        ),
      );
    });
  }

  // ── Set which conversation is currently open ──────────────────
  void _onSetCurrentConversation(
    SetCurrentConversationEvent event,
    Emitter<ChatState> emit,
  ) {
    if (event.conversationId.isEmpty) {
      if (event.owner != null && event.owner != _currentOwner) return;
      _currentConversationId = null;
      _currentOwner = null;
    } else {
      _currentConversationId = event.conversationId;
      _currentOwner = event.owner;
    }
    // Chat closed: hand the list (refreshed while the chat was open) back to
    // the conversations screen.
    if (_currentConversationId == null &&
        state is MessagesLoaded &&
        _conversationsLoaded) {
      emit(
        ConversationsLoaded(
          List<Map<String, dynamic>>.from(_conversationCache),
        ),
      );
    }
  }

  bool _conversationsLoaded = false;

  // ── Conversations list ────────────────────────────────────────
  Future<void> _onFetchConversations(
    FetchConversationsEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (_fetchingConversations) {
      _conversationsAskedAgain = true;
      return;
    }
    _fetchingConversations = true;
    // Only a first load shows a placeholder. A refresh keeps the list, and
    // never blanks a chat that is open.
    if (state is ChatInitial || state is ChatError) emit(ChatLoading());
    try {
      final conversations = await _repository.fetchConversations();
      _conversationCache = List<Map<String, dynamic>>.from(conversations);
      _conversationsLoaded = true;
      // A chat is open on its messages: keep them as the state (sending and
      // live messages need it) and update only the cache. Closing the chat
      // emits the list.
      if (_currentConversationId != null && state is MessagesLoaded) return;
      emit(ConversationsLoaded(conversations));
    } catch (e) {
      if (_currentConversationId != null && state is MessagesLoaded) return;
      emit(ChatError(e.toString()));
    } finally {
      _fetchingConversations = false;
      if (_conversationsAskedAgain && !isClosed) {
        _conversationsAskedAgain = false;
        add(FetchConversationsEvent());
      }
    }
  }

  // ── Initial messages load ─────────────────────────────────────
  Future<void> _onFetchMessages(
    FetchMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (!_fetchingMessages.add(event.conversationId)) return;
    // Messages of this same chat already on screen stay while they refresh.
    final showing =
        state is MessagesLoaded &&
        _messagesConversationId == event.conversationId;
    if (!showing) emit(ChatLoading());
    try {
      final messages = await _repository.fetchMessages(event.conversationId);
      // Tag historical messages with derived status so UI can render ticks
      final tagged = messages.map((m) {
        if (m.containsKey('_status')) return m;
        final isRead = m['is_read'] == true;
        final isDelivered = m['delivered_at'] != null;
        return <String, dynamic>{
          ...m,
          '_status': isRead
              ? 'read'
              : isDelivered
              ? 'delivered'
              : 'sent',
        };
      }).toList();
      _messagesConversationId = event.conversationId;
      emit(MessagesLoaded(tagged));
      // No markRead here: GET messages already marks them read on the server
      // and sends the read receipts.
    } catch (e) {
      emit(ChatError(e.toString()));
    } finally {
      _fetchingMessages.remove(event.conversationId);
    }
  }

  // ── Send message (optimistic) ─────────────────────────────────
  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is! MessagesLoaded) return;

    final currentMessages = List<Map<String, dynamic>>.from(
      (state as MessagesLoaded).messages,
    );

    // 1. Optimistically add the message with a temp ID
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = <String, dynamic>{
      'id': tempId,
      'sender_id': event.myUserId,
      'content': event.text,
      'message_type': 'text',
      '_status': 'sending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_read': false,
      'conversation_id': event.conversationId,
    };
    emit(MessagesLoaded([optimistic, ...currentMessages]));

    try {
      // 2. Persist to backend
      final sentMsg = await _repository.sendMessage(
        event.conversationId,
        event.text,
      );
      final realId = sentMsg['id']?.toString() ?? '';
      if (realId.isNotEmpty) _sentMessageIds.add(realId);

      // Check if a delivered receipt arrived while HTTP was in-flight
      final wasDelivered =
          realId.isNotEmpty && _pendingDelivered.remove(realId);

      // 3. Replace optimistic entry with confirmed message from server
      if (state is! MessagesLoaded) return;
      final updated = (state as MessagesLoaded).messages.map((m) {
        if (m['id'] == tempId) {
          // Honour forward-only status: sending → sent → delivered → read
          final status = wasDelivered ? 'delivered' : 'sent';
          return <String, dynamic>{...sentMsg, '_status': status};
        }
        return m;
      }).toList();
      emit(MessagesLoaded(List<Map<String, dynamic>>.from(updated)));

      // Also update conversation preview immediately for sender.
      _applyConversationPreview(
        emit,
        conversationId: event.conversationId,
        message: <String, dynamic>{
          'content': sentMsg['content'] ?? event.text,
          'message_type': sentMsg['message_type'] ?? 'text',
          'sender_id': sentMsg['sender_id'] ?? event.myUserId,
          'created_at':
              sentMsg['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
          'is_read': false,
        },
        incrementUnread: false,
      );
    } catch (e) {
      // Mark as failed so user knows to retry
      if (state is! MessagesLoaded) return;
      final failed = (state as MessagesLoaded).messages.map((m) {
        if (m['id'] == tempId) {
          return <String, dynamic>{...m, '_status': 'failed'};
        }
        return m;
      }).toList();
      emit(MessagesLoaded(List<Map<String, dynamic>>.from(failed)));
    }
  }

  // ── Incoming socket message ───────────────────────────────────
  void _onNewMessageReceived(
    NewMessageReceivedEvent event,
    Emitter<ChatState> emit,
  ) {
    final msg = event.message;
    final msgConvId = msg['conversation_id']?.toString();
    final msgId = msg['id']?.toString();

    if (state is MessagesLoaded && msgConvId == _currentConversationId) {
      final currentMessages = List<Map<String, dynamic>>.from(
        (state as MessagesLoaded).messages,
      );

      // Skip if already in list (prevents duplicates)
      if (msgId != null &&
          currentMessages.any((m) => m['id']?.toString() == msgId))
        return;

      // Skip own messages echoed back from socket (handled optimistically)
      if (msgId != null && _sentMessageIds.contains(msgId)) {
        _sentMessageIds.remove(msgId);
        return;
      }

      // Add incoming message — receiver sees it as delivered immediately
      emit(
        MessagesLoaded([
          <String, dynamic>{...msg, '_status': 'delivered'},
          ...currentMessages,
        ]),
      );

      // User is viewing this chat → mark as read silently so sender gets gold ticks
      if (msgConvId != null) {
        _markReadSoon(msgConvId);
      }
    } else {
      // Update conversation preview for every state except current-open-chat case.
      // This fixes missing unread/last-message updates when user is inside a
      // different chat screen (state == MessagesLoaded).
      _applyConversationPreview(
        emit,
        conversationId: msgConvId,
        message: <String, dynamic>{
          'content': msg['content'],
          'message_type': msg['message_type'] ?? 'text',
          'sender_id': msg['sender_id'],
          'created_at': msg['created_at'],
          'is_read': false,
        },
        incrementUnread: true,
      );

      if (state is ChatInitial) {
        add(FetchConversationsEvent());
      }
      if (_conversationCache.isEmpty) {
        add(FetchConversationsEvent());
      }
    }
  }

  void _markReadSoon(String conversationId) {
    if (_pendingMarkRead.containsKey(conversationId)) return;
    final last = _lastMarkRead[conversationId];
    final wait = last == null
        ? Duration.zero
        : const Duration(seconds: 1) - DateTime.now().difference(last);
    if (wait <= Duration.zero) {
      _lastMarkRead[conversationId] = DateTime.now();
      unawaited(_repository.markRead(conversationId));
      return;
    }
    _pendingMarkRead[conversationId] = Timer(wait, () {
      _pendingMarkRead.remove(conversationId);
      _lastMarkRead[conversationId] = DateTime.now();
      unawaited(_repository.markRead(conversationId));
    });
  }

  void _applyConversationPreview(
    Emitter<ChatState> emit, {
    required String? conversationId,
    required Map<String, dynamic> message,
    required bool incrementUnread,
  }) {
    if (conversationId == null || conversationId.isEmpty) return;
    if (_conversationCache.isEmpty) return;

    final convs = List<Map<String, dynamic>>.from(_conversationCache);
    final idx = convs.indexWhere(
      (c) => c['conversation_id']?.toString() == conversationId,
    );
    if (idx < 0) return;

    final updated = Map<String, dynamic>.from(convs[idx]);
    updated['last_message'] = message;
    updated['last_message_at'] = message['created_at'];
    if (incrementUnread) {
      updated['unread_count'] =
          ((updated['unread_count'] as num?)?.toInt() ?? 0) + 1;
    }
    convs[idx] = updated;
    final item = convs.removeAt(idx);
    convs.insert(0, item);
    _conversationCache = convs;

    if (state is ConversationsLoaded) {
      emit(
        ConversationsLoaded(
          List<Map<String, dynamic>>.from(_conversationCache),
        ),
      );
    }
  }

  // ── Delivered receipt (receiver was online when we sent) ──────
  void _onMessageDelivered(
    MessageDeliveredEvent event,
    Emitter<ChatState> emit,
  ) {
    if (event.messageId.isEmpty) return;
    if (event.conversationId != _currentConversationId) return;
    if (state is! MessagesLoaded) {
      // Message may not be in the list yet (still optimistic with temp ID)
      _pendingDelivered.add(event.messageId);
      return;
    }

    final messages = (state as MessagesLoaded).messages;
    bool found = false;
    final updated = messages.map((m) {
      final id = m['id']?.toString();
      // Only promote forward — never downgrade from 'read'
      if (id == event.messageId && m['_status'] != 'read') {
        found = true;
        return <String, dynamic>{...m, '_status': 'delivered'};
      }
      return m;
    }).toList();

    if (found) {
      emit(MessagesLoaded(List<Map<String, dynamic>>.from(updated)));
    } else {
      // Real message not yet in list (temp ID still in place) — store for later
      _pendingDelivered.add(event.messageId);
    }
  }

  // ── Read receipt (receiver opened the chat) ───────────────────
  void _onMessagesRead(MessagesReadEvent event, Emitter<ChatState> emit) {
    if (state is! MessagesLoaded) return;
    if (event.conversationId != _currentConversationId) return;

    final idSet = Set<String>.from(event.messageIds);
    final updated = (state as MessagesLoaded).messages.map((m) {
      if (idSet.contains(m['id']?.toString())) {
        return <String, dynamic>{...m, '_status': 'read', 'is_read': true};
      }
      return m;
    }).toList();
    emit(MessagesLoaded(List<Map<String, dynamic>>.from(updated)));
  }

  @override
  Future<void> close() {
    for (final t in _pendingMarkRead.values) {
      t.cancel();
    }
    _pendingMarkRead.clear();
    _socketSubscription?.cancel();
    _deliveredSubscription?.cancel();
    _readSubscription?.cancel();
    return super.close();
  }
}
