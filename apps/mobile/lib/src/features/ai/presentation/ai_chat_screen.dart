import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<_AiMessage> _messages = [
    _AiMessage(
      text: 'I am VEIL Assistant. I can help with privacy questions, '
          'device security, and messenger features. All conversations '
          'stay on this device.',
      isUser: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    ),
  ];
  bool _isTyping = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<VeilPalette>()!;

    return VeilShell(
      title: 'VEIL Assistant',
      actions: [
        IconButton(
          tooltip: 'Clear conversation',
          onPressed: () {
            setState(() {
              _messages.removeRange(1, _messages.length);
            });
          },
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      child: Column(
        children: [
          VeilInlineBanner(
            title: 'Local AI assistant',
            message: 'Responses are generated on-device or through an encrypted '
                'relay. No conversation data is stored on the server.',
            tone: VeilBannerTone.info,
            icon: Icons.smart_toy_outlined,
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilMetricStrip(
            items: [
              VeilMetricItem(label: 'Messages', value: '${_messages.length}'),
              VeilMetricItem(label: 'Model', value: 'Scaffold'),
              VeilMetricItem(label: 'Privacy', value: 'Local'),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          Expanded(
            child: _messages.isEmpty
                ? const VeilEmptyState(
                    title: 'Ask anything',
                    body: 'Start a conversation with the VEIL assistant.',
                    icon: Icons.smart_toy_outlined,
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: VeilSpace.sm),
                    itemBuilder: (context, index) {
                      if (_isTyping && index == _messages.length) {
                        return _buildTypingIndicator(palette);
                      }
                      return _buildMessageBubble(_messages[index], palette);
                    },
                  ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilComposer(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_isTyping,
            onSubmit: _sendMessage,
            helper: 'Ask about privacy, security, or VEIL features.',
            trailing: VeilButton(
              expanded: false,
              onPressed: _isTyping ? null : _sendMessage,
              label: _isTyping ? 'Thinking' : 'Ask',
              icon: Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_AiMessage message, VeilPalette palette) {
    return Align(
      alignment:
          message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: VeilSurfaceCard(
          selected: message.isUser,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    message.isUser
                        ? Icons.person_outline_rounded
                        : Icons.smart_toy_outlined,
                    size: VeilIconSize.sm,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: VeilSpace.xs),
                  Text(
                    message.isUser ? 'You' : 'VEIL Assistant',
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VeilSpace.xs),
              SelectableText(
                message.text,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(VeilPalette palette) {
    return Align(
      alignment: Alignment.centerLeft,
      child: VeilSurfaceCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: VeilIconSize.sm,
              height: VeilIconSize.sm,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primary,
              ),
            ),
            const SizedBox(width: VeilSpace.sm),
            Text(
              'Thinking...',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(_AiMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    // Simulate AI response delay
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    setState(() {
      _isTyping = false;
      _messages.add(_AiMessage(
        text: _generateResponse(text),
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: VeilMotion.normal,
        curve: VeilMotion.emphasize,
      );
    });
  }

  String _generateResponse(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('privacy') || lower.contains('secure')) {
      return 'VEIL is built on a no-backup, no-recovery model. Your '
          'messages are encrypted on-device before reaching the relay. '
          'The server never stores plaintext content.';
    }
    if (lower.contains('transfer') || lower.contains('device')) {
      return 'Device transfer requires your old device to be active. '
          'This ensures that identity keys never leave device-side '
          'storage. No cloud recovery path exists by design.';
    }
    if (lower.contains('group') || lower.contains('chat')) {
      return 'Group chats use the same envelope encryption model as '
          'direct messages. Each member receives an individually '
          'encrypted copy of the message through the relay.';
    }
    if (lower.contains('call') || lower.contains('voice') || lower.contains('video')) {
      return 'Voice and video calls are routed peer-to-peer when '
          'possible. When a direct connection cannot be established, '
          'an encrypted relay fallback is used. Call metadata is minimal.';
    }
    if (lower.contains('story') || lower.contains('moment')) {
      return 'Stories expire after 24 hours and are stored locally. '
          'View counts are tracked on-device. The relay only handles '
          'encrypted content distribution.';
    }
    return 'AI assistant integration requires an LLM API connection. '
        'This is currently a scaffold. When connected, all queries '
        'will be processed through an encrypted relay to preserve '
        'VEIL privacy guarantees.';
  }
}

class _AiMessage {
  const _AiMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  final String text;
  final bool isUser;
  final DateTime timestamp;
}
