import 'package:flutter/material.dart';
import 'package:memoro/core/constants/dimensions.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/theme/app_color_palette.dart';
import '../../../core/services/chat_service.dart';

class ChatConversationPage extends StatefulWidget {
  const ChatConversationPage({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.title,
    this.avatarUrl = '',
  });

  final String chatId;
  final String currentUserId;
  final String title;
  final String avatarUrl;

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static const List<String> _quickReplies = <String>[
    'Yes, please',
    'No thank you',
    'Love you',
  ];

  bool _sending = false;
  bool _desiredInChat = false;
  Future<void> _presenceQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _enqueueInChat(true);
  }

  Future<void> _enqueueInChat(bool inChat) {
    if (_desiredInChat == inChat) return _presenceQueue;
    _desiredInChat = inChat;
    _presenceQueue = _presenceQueue.then(
      (_) => ChatService.setInChatPresence(
        chatId: widget.chatId,
        uid: widget.currentUserId,
        inChat: inChat,
      ),
    );
    return _presenceQueue;
  }

  @override
  void dispose() {
    _enqueueInChat(false);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatService.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUserId,
        text: text,
      );
      _messageController.clear();
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(BuildContext context, DateTime? value) {
    if (value == null) return '';
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(value));
  }

  Future<void> _sendQuickReply(String text) async {
    _messageController.text = text;
    await _sendMessage();
  }

  Widget _headerAvatar() {
    if (widget.avatarUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(widget.avatarUrl.trim()),
      );
    }
    return const CircleAvatar(
      radius: 18,
      backgroundColor: Colors.white,
      child: Icon(Icons.person, color: AppColorPalette.blueSteel),
    );
  }

  Widget _messageBubble({
    required BuildContext context,
    required ChatMessage message,
    required bool isMine,
  }) {
    final bubbleColor = isMine ? AppColorPalette.blueSteel : Colors.white;
    final textColor = isMine ? Colors.white : Colors.black87;
    final align = isMine
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text(
                  widget.title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColorPalette.grey,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            Container(
              constraints: const BoxConstraints(maxWidth: 295),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: textColor,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _formatTime(context, message.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColorPalette.grey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _enqueueInChat(false);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleSpacing: 0,
          title: Row(
            children: [
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Chat With ${widget.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _headerAvatar(),
              rowSpace,
              rowSpace,
              rowSpace,
              rowSpace,
              rowSpace,
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),

                child: StreamBuilder<List<ChatMessage>>(
                  stream: ChatService.watchMessages(widget.chatId),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? const <ChatMessage>[];
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToBottom();
                    });
                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Today',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppColorPalette.grey,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.zero,
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              final isMine =
                                  message.senderId == widget.currentUserId;
                              return _messageBubble(
                                context: context,
                                message: message,
                                isMine: isMine,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickReplies.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final text = _quickReplies[index];
                          return ActionChip(
                            onPressed: _sending
                                ? null
                                : () => _sendQuickReply(text),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.8,
                            ),
                            label: Text(
                              text,
                              style: const TextStyle(
                                color: AppColorPalette.blueSteel,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            side: BorderSide.none,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Type message...',
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.9),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _sendMessage,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              backgroundColor: AppColorPalette.blueSteel,
                              foregroundColor: Colors.white,
                            ),
                            child: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
