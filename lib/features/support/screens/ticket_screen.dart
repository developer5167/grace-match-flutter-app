import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injection.dart' as di;
import '../../../core/network/socket_service.dart';
import '../../../core/notifications/push_center.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/support_repository.dart';

/// One support conversation.
///
/// Deliberately looks like the chat the member already knows, because it is
/// the same act — writing to a person and waiting for a reply. The only
/// difference worth showing is that a resolved conversation stops accepting
/// messages, and says so rather than silently failing.
class TicketScreen extends StatefulWidget {
  final String ticketId;
  const TicketScreen({super.key, required this.ticketId});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  final _repo = SupportRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  SupportTicket? _ticket;
  List<SupportMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  Object? _error;
  File? _pending;
  StreamSubscription<SupportEvent>? _live;

  @override
  void initState() {
    super.initState();
    PushCenter.clear(['support:${widget.ticketId}']);
    _load();

    // A staff reply lands in an open thread without the member backing out
    // and reopening. The push notification is still what reaches them when
    // the app is closed; this only covers the case where they are already
    // looking at the screen and waiting.
    _live = di.sl<SocketService>().supportStream.listen((e) {
      if (e.ticketId == widget.ticketId && mounted) _load();
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Support only needs to read it, and a 12-megapixel screenshot over
      // mobile data is a slow way to send a picture of an error message.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _pending = File(picked.path));
    }
  }

  Future<void> _load() async {
    try {
      final t = await _repo.thread(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = t.ticket;
        _messages = t.messages;
        _loading = false;
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending == null) || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = await _repo.reply(
        widget.ticketId,
        text,
        imagePath: _pending?.path,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
        _input.clear();
        _pending = null;
        _sending = false;
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settled = _ticket?.isSettled ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_ticket?.subject ?? 'Support',
                style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_ticket != null)
              Text(_ticket!.statusLabel,
                  style: AppTextStyles.overline.copyWith(
                    color: _ticket!.status == 'awaiting_member'
                        ? AppColors.gold
                        : AppColors.textTertiary,
                  )),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          if (settled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.surface,
              child: Text(
                _ticket!.status == 'closed'
                    ? 'This conversation is closed. Start a new one if you still need help.'
                    : 'Marked as resolved. Reply below if it is still happening.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          if (_ticket?.status != 'closed') _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text('Could not load this conversation',
                  style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
                child: Text('Try again',
                    style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _Bubble(message: _messages[i]),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.surfaceHighest)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // What is about to be sent, with a way to change your mind.
            if (_pending != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_pending!, width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Photo attached',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _pending = null),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Only once support has asked for a photo. The server refuses the
            // upload otherwise, so this is a convenience, not the control.
            if (_ticket?.attachmentsEnabled == true) ...[
              GestureDetector(
                onTap: () { AppHaptics.light(); _pickImage(); },
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surfaceHighest),
                  ),
                  child: const Icon(Icons.attach_file_rounded,
                      size: 19, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                style: AppTextStyles.bodyMedium,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a message…',
                  hintStyle: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.surfaceHighest),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.surfaceHighest),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.goldMild),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () { AppHaptics.light(); _send(); },
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                    color: AppColors.gold, shape: BoxShape.circle),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            color: AppColors.textOnGold, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: AppColors.textOnGold, size: 19),
              ),
            ),
          ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final SupportMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final system = message.senderType == 'system';

    if (system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(message.body ?? '',
              style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: mine ? AppColors.goldSubtle : AppColors.surfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: Border.all(
              color: mine ? AppColors.goldMild : AppColors.surfaceHighest),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(message.senderName ?? 'Support',
                    style: AppTextStyles.overline.copyWith(color: AppColors.gold)),
              ),
            if (message.body != null && message.body!.isNotEmpty)
              Text(message.body!, style: AppTextStyles.bodyMedium),
            if (message.attachmentUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(message.attachmentUrl!,
                    height: 150, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ],
            const SizedBox(height: 4),
            Text(DateFormat('dd MMM, HH:mm').format(message.createdAt),
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.textTertiary, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}
