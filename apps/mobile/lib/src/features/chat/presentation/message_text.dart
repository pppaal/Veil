import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/link_opener.dart';
import '../../../core/safety/links.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../conversations/presentation/conversation_list_logic.dart';

/// A message's text, with every link in it (an http or https address, or a
/// bare domain such as example.com) drawn as one: underlined, in
/// [linkColor] (the brand colour on someone else's bubble, white on the
/// user's own), and a tap on it handed to [onLinkTap], which decides
/// whether a sheet asks first (see openMessageLink). A screen reader calls
/// each link "Link, " and its domain. Without [onLinkTap] the links are
/// drawn and do nothing.
///
/// While a chat search runs ([searchQuery]) its hits are drawn in bold and
/// the links as plain text: the search wins. The phone never fetches,
/// previews or expands a link; it is found in the text alone.
class MessageText extends StatefulWidget {
  const MessageText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    this.searchQuery,
    this.onLinkTap,
  });

  final String text;
  final TextStyle? style;
  final Color linkColor;
  final String? searchQuery;
  final void Function(FoundLink link)? onLinkTap;

  @override
  State<MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<MessageText> {
  List<FoundLink> _links = const [];
  List<TapGestureRecognizer> _recognizers = const [];

  @override
  void initState() {
    super.initState();
    _findLinks();
  }

  @override
  void didUpdateWidget(MessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _findLinks();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _findLinks() {
    _disposeRecognizers();
    _links = [
      for (final link in findLinks(widget.text))
        if (isOpenableLink(link.uri)) link,
    ];
    _recognizers = [
      // Read when tapped, so a new callback needs no new recognizer.
      for (final link in _links) TapGestureRecognizer()..onTap = () => widget.onLinkTap?.call(link),
    ];
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final query = widget.searchQuery?.trim() ?? '';
    if (query.isNotEmpty) {
      return Text.rich(
        TextSpan(
          children: buildSearchHighlightTextSpans(
            text: widget.text,
            query: query,
            baseStyle: style,
            highlightStyle: style?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    if (_links.isEmpty) return Text(widget.text, style: style);
    final l10n = AppLocalizations.of(context);
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final tappable = widget.onLinkTap != null;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final (index, link) in _links.indexed) {
      if (link.start < cursor) continue;
      if (link.start > cursor) spans.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      spans.add(TextSpan(
        text: widget.text.substring(link.start, link.end),
        style: linkStyle,
        recognizer: tappable ? _recognizers[index] : null,
        semanticsLabel: l10n.linkSemanticsLabel(link.registrableDomain),
      ));
      cursor = link.end;
    }
    if (cursor < widget.text.length) spans.add(TextSpan(text: widget.text.substring(cursor)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
