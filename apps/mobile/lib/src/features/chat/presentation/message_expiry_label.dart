import 'dart:async';

import 'package:flutter/widgets.dart';

import 'message_expiration.dart';

/// "Expires in …" for one message, kept current by a one-shot timer armed
/// for the moment its text next changes, so only this label rebuilds.
class MessageExpiryLabel extends StatefulWidget {
  const MessageExpiryLabel({super.key, required this.expiresAt, this.style});

  final DateTime expiresAt;
  final TextStyle? style;

  @override
  State<MessageExpiryLabel> createState() => _MessageExpiryLabelState();
}

class _MessageExpiryLabelState extends State<MessageExpiryLabel> {
  Timer? _nextChange;

  @override
  void initState() {
    super.initState();
    _armNextChange();
  }

  @override
  void didUpdateWidget(covariant MessageExpiryLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) _armNextChange();
  }

  @override
  void dispose() {
    _nextChange?.cancel();
    super.dispose();
  }

  void _armNextChange() {
    _nextChange?.cancel();
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    // The text counts whole seconds, minutes, hours or days, and changes
    // just after the remaining time drops below its current whole count.
    final unit = remaining < const Duration(minutes: 1)
        ? const Duration(seconds: 1)
        : remaining < const Duration(hours: 1)
            ? const Duration(minutes: 1)
            : remaining < const Duration(days: 1)
                ? const Duration(hours: 1)
                : const Duration(days: 1);
    final untilChange = Duration(microseconds: remaining.inMicroseconds % unit.inMicroseconds);
    _nextChange = Timer(untilChange + const Duration(milliseconds: 1), () {
      if (!mounted) return;
      setState(_armNextChange);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMessageExpiry(widget.expiresAt),
      style: widget.style,
      overflow: TextOverflow.ellipsis,
    );
  }
}
