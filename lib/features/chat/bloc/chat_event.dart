import 'package:equatable/equatable.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class FetchConversationsEvent extends ChatEvent {}

class FetchMessagesEvent extends ChatEvent {
  final String conversationId;
  const FetchMessagesEvent(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

class SetCurrentConversationEvent extends ChatEvent {
  final String conversationId;

  /// The chat screen that sent this. An empty [conversationId] (leaving)
  /// only clears the conversation that same screen set, so a chat closing
  /// late — still animating out while the next one opens — cannot clear
  /// the one now on screen. Null clears whatever is set.
  final Object? owner;
  const SetCurrentConversationEvent(this.conversationId, {this.owner});

  @override
  List<Object?> get props => [conversationId];
}

class SendMessageEvent extends ChatEvent {
  final String conversationId;
  final String text;
  final String? myUserId;
  const SendMessageEvent({
    required this.conversationId,
    required this.text,
    this.myUserId,
  });

  @override
  List<Object?> get props => [conversationId, text, myUserId];
}

class NewMessageReceivedEvent extends ChatEvent {
  final Map<String, dynamic> message;
  const NewMessageReceivedEvent(this.message);

  @override
  List<Object?> get props => [message];
}

class MessageDeliveredEvent extends ChatEvent {
  final String messageId;
  final String conversationId;
  const MessageDeliveredEvent({
    required this.messageId,
    required this.conversationId,
  });

  @override
  List<Object?> get props => [messageId, conversationId];
}

class MessagesReadEvent extends ChatEvent {
  final List<String> messageIds;
  final String conversationId;
  const MessagesReadEvent({
    required this.messageIds,
    required this.conversationId,
  });

  @override
  List<Object?> get props => [messageIds, conversationId];
}
