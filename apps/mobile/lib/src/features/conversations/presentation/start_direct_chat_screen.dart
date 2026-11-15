import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'conversation_list_logic.dart';

/// Opens a 1:1 chat with the person whose handle is typed: the field, with
/// how to type it under it (or why it opened nothing), and the button.
class StartDirectChatScreen extends ConsumerStatefulWidget {
  const StartDirectChatScreen({super.key});

  @override
  ConsumerState<StartDirectChatScreen> createState() => _StartDirectChatScreenState();
}

class _StartDirectChatScreenState extends ConsumerState<StartDirectChatScreen> {
  final _handleController = TextEditingController();
  bool _opening = false;

  // Whether the last attempt of this screen failed; a failure elsewhere in
  // the messenger is not this screen's to show.
  bool _failed = false;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  String get _handle => _handleController.text.trim().replaceAll(RegExp(r'^@'), '');

  Future<void> _open() async {
    final handle = _handle;
    if (handle.isEmpty || _opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final conversationId = await ref.read(messengerControllerProvider).startConversationByHandle(handle);
    if (!mounted) return;
    if (conversationId == null) {
      setState(() {
        _opening = false;
        _failed = true;
      });
      return;
    }
    // Beside the list the new conversation is already on screen; on a phone
    // it opens in this screen's place.
    if (shouldUseWideConversationLayout(MediaQuery.sizeOf(context).width)) {
      context.pop();
    } else {
      context.pushReplacement('/chat/$conversationId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      title: l10n.startDirectTitle,
      maxWidth: 560,
      child: ListView(
        padding: VeilShell.formPadding,
        children: [
          TextField(
            controller: _handleController,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() => _failed = false),
            onSubmitted: (_) => _open(),
            decoration: InputDecoration(
              labelText: l10n.startDirectInputLabel,
              hintText: l10n.startDirectHandleHint,
              prefixText: '@',
              helperText: l10n.startDirectFieldCaption,
              helperMaxLines: 2,
              errorText: _failed ? l10n.startDirectHandleError : null,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilButton(
            onPressed: _opening || _handle.isEmpty ? null : _open,
            label: _opening ? l10n.startDirectOpening : l10n.startDirectOpenButton,
          ),
        ],
      ),
    );
  }
}
