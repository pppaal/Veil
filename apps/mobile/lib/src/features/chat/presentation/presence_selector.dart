import 'package:flutter/widgets.dart';

import '../../conversations/data/messenger/presence_typing_service.dart';

/// Rebuilds [builder] when [select] of the presence signals changes, and
/// only then: a peer typing in another conversation rebuilds nothing here,
/// and nothing of the screen around it.
class PresenceSelector<T> extends StatefulWidget {
  const PresenceSelector({super.key, required this.presence, required this.select, required this.builder});

  final PresenceTypingService presence;
  final T Function(PresenceTypingService presence) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<PresenceSelector<T>> createState() => _PresenceSelectorState<T>();
}

class _PresenceSelectorState<T> extends State<PresenceSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.presence);
    widget.presence.addListener(_onPresenceChanged);
  }

  @override
  void didUpdateWidget(covariant PresenceSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presence, widget.presence)) {
      oldWidget.presence.removeListener(_onPresenceChanged);
      widget.presence.addListener(_onPresenceChanged);
    }
    _value = widget.select(widget.presence);
  }

  @override
  void dispose() {
    widget.presence.removeListener(_onPresenceChanged);
    super.dispose();
  }

  void _onPresenceChanged() {
    final next = widget.select(widget.presence);
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
