import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../chat/presentation/message_time.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/one_time_link_service.dart';

/// Compose a one-time secret link: type a secret, encrypt on-device, store
/// only the ciphertext, and share the resulting burn-after-read link. The
/// form, with the one rule of such a link under it, then the button; the
/// link that was made follows.
class OneTimeLinkScreen extends StatefulWidget {
  const OneTimeLinkScreen({super.key, OneTimeLinkService? service, DateTime Function() clock = DateTime.now})
      : _service = service,
        _clock = clock;

  final OneTimeLinkService? _service;

  // The phone's clock, against which the link's expiry says "today" or
  // "tomorrow".
  final DateTime Function() _clock;

  @override
  State<OneTimeLinkScreen> createState() => _OneTimeLinkScreenState();
}

class _OneTimeLinkScreenState extends State<OneTimeLinkScreen> {
  late final OneTimeLinkService _service = widget._service ?? OneTimeLinkService();
  final _secret = TextEditingController();
  final _pass = TextEditingController();
  final _resultKey = GlobalKey();
  bool _usePass = false;
  bool _busy = false;
  CreatedOneTimeLink? _link;
  bool _failed = false;

  @override
  void dispose() {
    _secret.dispose();
    _pass.dispose();
    super.dispose();
  }

  // A passphrase that was asked for must be given: an empty one would put
  // the key back into the link without saying so.
  bool get _ready => _secret.text.trim().isNotEmpty && (!_usePass || _pass.text.isNotEmpty);

  // The link on screen is the one the form, as it stands, made. Once the
  // secret, the passphrase or the switch changes, the link would be shown
  // beside words it does not carry and a lock it may not have, so it goes.
  void _edited() => setState(() => _link = null);

  Future<void> _generate() async {
    final secret = _secret.text.trim();
    if (!_ready || _busy) return;
    final passphrase = _usePass ? _pass.text : null;
    setState(() {
      _busy = true;
      _failed = false;
      _link = null;
    });
    try {
      final link = await _service.create(secret, passphrase: passphrase);
      if (!mounted) return;
      // Sealing takes a moment, and the fields stay open meanwhile: a link
      // for what the form no longer says is not shown.
      if (_secret.text.trim() != secret || (_usePass ? _pass.text : null) != passphrase) return;
      setState(() => _link = link);
      // The link appears under the button, which a small phone or an open
      // keyboard may have at the bottom edge.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final result = _resultKey.currentContext;
        if (result != null) Scrollable.ensureVisible(result, duration: VeilMotion.normal, alignment: 0.1);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final link = _link;
    return VeilShell(
      title: l10n.oneTimeLinkTitle,
      grouped: true,
      maxWidth: 560,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: VeilSpace.xxl),
        children: [
          const SizedBox(height: VeilSpace.md),
          VeilGroup(
            footer: l10n.oneTimeLinkFooter,
            children: [
              VeilRow.field(
                // The hint names the field on screen; a screen reader hears
                // its name on the field itself.
                field: Semantics(
                  label: l10n.oneTimeLinkSecretLabel,
                  child: TextField(
                    controller: _secret,
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (_) => _edited(),
                    decoration: InputDecoration(hintText: l10n.oneTimeLinkSecretHint),
                  ),
                ),
              ),
              VeilRow(
                title: l10n.oneTimeLinkUsePassphrase,
                switchValue: _usePass,
                onSwitch: _busy
                    ? null
                    : (value) {
                        _usePass = value;
                        _edited();
                      },
              ),
              if (_usePass)
                VeilRow.field(
                  title: l10n.oneTimeLinkPassphraseLabel,
                  field: TextField(
                    controller: _pass,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => _edited(),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
            child: VeilButton(
              label: _busy ? l10n.oneTimeLinkCreating : l10n.oneTimeLinkCreate,
              onPressed: _busy || !_ready ? null : _generate,
            ),
          ),
          // A failure is one line under the button that tries again, not a
          // notice: there is nothing to decide, and the button is the retry.
          if (_failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.xs, VeilSpace.md, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.oneTimeLinkFailed,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.veilPalette.danger),
                ),
              ),
            ),
          if (link != null) ...[
            const SizedBox(height: VeilSpace.lg),
            _CreatedLink(key: _resultKey, link: link, now: widget._clock()),
          ],
        ],
      ),
    );
  }
}

/// The link that was made: the link itself and the button that copies it,
/// and under them when it is deleted unopened and, if it was sealed with
/// one, the reminder to send its passphrase apart.
class _CreatedLink extends StatelessWidget {
  const _CreatedLink({super.key, required this.link, required this.now});

  final CreatedOneTimeLink link;

  /// When the link is shown, against which its expiry is said.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final expiresAt = link.expiresAt?.toLocal();
    final notes = [
      if (expiresAt != null) l10n.oneTimeLinkExpires(MessageTimeFormat.of(context).dayAndTime(expiresAt, now: now)),
      if (link.passphraseLocked) l10n.oneTimeLinkSendPassphraseApart,
    ];
    return VeilGroup(
      footer: notes.isEmpty ? null : notes.join(' '),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
          child: SelectableText(
            link.url,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.4),
          ),
        ),
        VeilRow(
          title: l10n.oneTimeLinkCopy,
          leading: const Icon(Icons.copy_outlined, size: 20),
          trailing: const SizedBox.shrink(),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: link.url));
            if (context.mounted) showVeilToast(context, l10n.oneTimeLinkCopied);
          },
        ),
      ],
    );
  }
}
