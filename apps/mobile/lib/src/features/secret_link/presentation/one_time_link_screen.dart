import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/one_time_link_service.dart';

/// Compose a one-time secret link: type a secret, encrypt on-device, store
/// only the ciphertext, and share the resulting burn-after-read link. The
/// form comes first, with what the link does under it; the link that was
/// made follows, and last what such a link does not protect.
class OneTimeLinkScreen extends StatefulWidget {
  const OneTimeLinkScreen({super.key, OneTimeLinkService? service}) : _service = service;

  final OneTimeLinkService? _service;

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
          VeilGroup(
            header: l10n.oneTimeLinkSecretLabel,
            footer: l10n.oneTimeLinkFooter,
            children: [
              VeilRow.field(
                // The group's header names the field on screen; a screen
                // reader hears it on the field itself.
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
                subtitle: l10n.oneTimeLinkUsePassphraseCaption,
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
            _CreatedLink(key: _resultKey, link: link),
          ],
          // What such a link does not protect, set apart from the form: the
          // one place it is said.
          const SizedBox(height: VeilSpace.md),
          VeilGroup(
            header: l10n.oneTimeLinkLimitsLabel,
            children: [
              for (final limit in [l10n.oneTimeLinkLimitHolder, l10n.oneTimeLinkLimitReader, l10n.oneTimeLinkLimitRelay])
                _Paragraph(limit),
            ],
          ),
        ],
      ),
    );
  }
}

/// The link that was made: its QR code, the link itself with the button
/// that copies it, and under them when it is deleted unopened and, if it
/// was sealed with one, the reminder to send its passphrase apart.
class _CreatedLink extends StatelessWidget {
  const _CreatedLink({super.key, required this.link});

  final CreatedOneTimeLink link;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final expiresAt = link.expiresAt?.toLocal();
    final notes = [
      if (expiresAt != null) l10n.oneTimeLinkExpires(DateFormat.MMMd(l10n.localeName).add_Hm().format(expiresAt)),
      if (link.passphraseLocked) l10n.oneTimeLinkSendPassphraseApart,
    ];
    return VeilGroup(
      footer: notes.isEmpty ? null : notes.join(' '),
      children: [
        Padding(
          padding: const EdgeInsets.all(VeilSpace.md),
          child: Center(
            // A QR code is read dark on light, whatever the theme.
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(VeilRadius.md)),
              child: Padding(
                padding: const EdgeInsets.all(VeilSpace.sm),
                child: QrImageView(data: link.url, size: 180, padding: EdgeInsets.zero, backgroundColor: Colors.white),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: VeilSpace.md, end: VeilSpace.xxs),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: VeilSpace.sm),
                  child: SelectableText(
                    link.url,
                    // `monospace` is Android's name for its mono font; iOS has Menlo.
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo'], height: 1.4),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.oneTimeLinkCopy,
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link.url));
                  if (context.mounted) showVeilToast(context, l10n.oneTimeLinkCopied);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A sentence as a row of its own: plain body text, wrapping as it needs.
class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: 11),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
