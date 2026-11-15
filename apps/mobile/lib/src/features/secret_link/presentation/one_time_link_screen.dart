import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_grouped.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/one_time_link_service.dart';

/// Compose a one-time secret link: type a secret, encrypt on-device, store
/// only the ciphertext, and share the resulting burn-after-read link. The
/// form comes first; what the link protects, and what it does not, is said
/// under it.
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
      maxWidth: 560,
      padding: EdgeInsets.zero,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(VeilSpace.lg, VeilSpace.lg, VeilSpace.lg, VeilSpace.xl),
        children: [
          TextField(
            controller: _secret,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) => _edited(),
            decoration: InputDecoration(
              labelText: l10n.oneTimeLinkSecretLabel,
              hintText: l10n.oneTimeLinkSecretHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilGroup(
            children: [
              VeilGroupSwitchRow(
                icon: Icons.key_outlined,
                title: l10n.oneTimeLinkUsePassphrase,
                subtitle: l10n.oneTimeLinkUsePassphraseBody,
                value: _usePass,
                onChanged: _busy
                    ? null
                    : (value) {
                        _usePass = value;
                        _edited();
                      },
              ),
            ],
          ),
          if (_usePass) ...[
            const SizedBox(height: VeilSpace.sm),
            TextField(
              controller: _pass,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => _edited(),
              decoration: InputDecoration(labelText: l10n.oneTimeLinkPassphraseLabel),
            ),
          ],
          const SizedBox(height: VeilSpace.md),
          VeilButton(
            icon: Icons.link_rounded,
            label: _busy ? l10n.oneTimeLinkCreating : l10n.oneTimeLinkCreate,
            onPressed: _busy || !_ready ? null : _generate,
          ),
          if (_failed) ...[
            const SizedBox(height: VeilSpace.sm),
            VeilInlineBanner(message: l10n.oneTimeLinkFailed, tone: VeilBannerTone.danger),
          ],
          if (link != null) ...[
            const SizedBox(height: VeilSpace.md),
            _CreatedLink(key: _resultKey, link: link),
          ],
          const SizedBox(height: VeilSpace.xl),
          _Facts(
            label: l10n.oneTimeLinkProtectsLabel,
            icon: Icons.check_circle_outline_rounded,
            color: context.veilPalette.success,
            facts: [l10n.oneTimeLinkProtectsEncrypted, l10n.oneTimeLinkProtectsBurn],
          ),
          const SizedBox(height: VeilSpace.lg),
          _Facts(
            label: l10n.oneTimeLinkLimitsLabel,
            icon: Icons.error_outline_rounded,
            color: context.veilPalette.warning,
            facts: [l10n.oneTimeLinkLimitHolder, l10n.oneTimeLinkLimitReader, l10n.oneTimeLinkLimitRelay],
          ),
        ],
      ),
    );
  }
}

/// The link that was made: its QR code, the link itself, when it expires
/// unopened, the reminder to send its passphrase apart if it was sealed with
/// one, and the button that copies it.
class _CreatedLink extends StatelessWidget {
  const _CreatedLink({super.key, required this.link});

  final CreatedOneTimeLink link;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final expiresAt = link.expiresAt?.toLocal();
    return VeilSurfaceCard(
      padding: const EdgeInsets.all(VeilSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            // A QR code is read dark on light, whatever the theme.
            child: QrImageView(data: link.url, size: 180, backgroundColor: Colors.white),
          ),
          const SizedBox(height: VeilSpace.sm),
          SelectableText(link.url, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
          const SizedBox(height: VeilSpace.xs),
          VeilCopy(
            [
              if (expiresAt != null)
                l10n.oneTimeLinkExpires(DateFormat.MMMd(l10n.localeName).add_Hm().format(expiresAt)),
              if (link.passphraseLocked) l10n.oneTimeLinkSendPassphraseApart,
            ].join(' '),
            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: VeilSpace.sm),
          VeilButton(
            tone: VeilButtonTone.secondary,
            icon: Icons.copy_rounded,
            label: l10n.oneTimeLinkCopy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link.url));
              if (context.mounted) VeilToast.show(context, message: l10n.oneTimeLinkCopied);
            },
          ),
        ],
      ),
    );
  }
}

/// A short list of facts under one label, each with the same mark.
class _Facts extends StatelessWidget {
  const _Facts({required this.label, required this.icon, required this.color, required this.facts});

  final String label;
  final IconData icon;
  final Color color;
  final List<String> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VeilGroup(
      label: label,
      children: [
        for (final fact in facts)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md, vertical: VeilSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: VeilIconSize.sm, color: color),
                ),
                const SizedBox(width: VeilSpace.sm),
                Expanded(
                  child: VeilCopy(fact, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
