import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  // Cache conversations so we can still render them while the bloc is in
  // a transient state (e.g. MessagesLoaded / ChatLoading after returning from chat).
  List<Map<String, dynamic>> _cachedConversations = [];

  String _formatTime(dynamic raw) {
    if (raw == null) return '';
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is String && raw.isNotEmpty) {
      dt = DateTime.tryParse(raw)?.toLocal();
    }
    if (dt == null) return '';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _extractLastMessage(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map) {
      final map = value.cast<dynamic, dynamic>();
      final content = map['content']?.toString();
      if (content != null && content.isNotEmpty) return content;
      final type = map['message_type']?.toString();
      if (type == 'photo') return 'Sent a photo';
    }
    return 'Start a conversation';
  }

  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(FetchConversationsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        // Keep the cache warm whenever we get fresh data.
        if (state is ConversationsLoaded) {
          _cachedConversations = state.conversations;
        }

        // Decide what to show in the body:
        // - fresh load with no cache yet → spinner
        // - error → error text
        // - anything else (including MessagesLoaded / ChatLoading) with cached data → use cache
        Widget body;
        if (state is ChatError) {
          body = Center(
            child: Text(state.message, style: const TextStyle(color: Colors.white)),
          );
        } else if (state is ConversationsLoaded) {
          body = _buildConversationList(state.conversations);
        } else if (_cachedConversations.isNotEmpty) {
          body = _buildConversationList(_cachedConversations);
        } else {
          body = Center(child: CircularProgressIndicator(color: AppColors.gold));
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Chat', style: AppTextStyles.headlineMedium),
            elevation: 0,
            backgroundColor: AppColors.background,
            actions: [
              IconButton(
                icon: Icon(Icons.shield_rounded, color: AppColors.gold),
                onPressed: () {},
              )
            ],
          ),
          body: body,
        );
      },
    );
  }

  Widget _buildConversationList(List<Map<String, dynamic>> conversations) {
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 64, color: AppColors.surfaceHighest),
            const SizedBox(height: 16),
            Text('No active chats', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            Text('Matches will appear here once both like each other.', style: AppTextStyles.bodyMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final unreadCount = int.tryParse('${conv['unread_count'] ?? 0}') ?? 0;
        final isUnread = unreadCount > 0;
        final name = (conv['other_user_name'] ?? 'Match').toString();
        final lastMsg = _extractLastMessage(conv['last_message']);
        final time = _formatTime(conv['last_message_at']);
        final photo = conv['other_user_photo']?.toString();
        final conversationId = conv['conversation_id']?.toString();
        final otherUserId = conv['other_user_id']?.toString();
        final isOnline = conv['is_online'] == true;

        return InkWell(
          onTap: () async {
            if (conversationId == null || conversationId.isEmpty) return;
            // Capture bloc reference BEFORE the async gap so it's safe after pop.
            final bloc = context.read<ChatBloc>();
            await context.push('/chat/$conversationId', extra: {
              'name': name,
              'photo': photo,
              'userId': otherUserId,
            });
            bloc.add(FetchConversationsEvent());
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: isUnread ? AppColors.surfaceElevated.withAlpha(50) : null,
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceHighest,
                        border: isUnread ? Border.all(color: AppColors.gold, width: 2) : null,
                        image: photo != null && photo.isNotEmpty
                          ? DecorationImage(image: CachedNetworkImageProvider(photo), fit: BoxFit.cover)
                          : null,
                      ),
                      child: photo == null || photo.isEmpty
                        ? const Icon(Icons.person, color: AppColors.textTertiary)
                        : null,
                    ),
                    // Online/offline dot — bottom-right of avatar
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline
                              ? const Color(0xFF4CAF50)
                              : AppColors.surfaceHighest,
                          border: Border.all(
                            color: AppColors.background,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    if (isUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.background, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            name,
                            style: AppTextStyles.labelLarge.copyWith(
                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                          Text(
                            time,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isUnread ? AppColors.gold : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lastMsg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: isUnread ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

