import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/one_time_link_service.dart';

/// Compose a one-time secret link: type a secret, encrypt on-device, store
/// only the ciphertext, and share the resulting burn-after-read link.
class OneTimeLinkScreen extends StatefulWidget {
  const OneTimeLinkScreen({super.key, OneTimeLinkService? service})
      : _service = service;

  final OneTimeLinkService? _service;

  @override
  State<OneTimeLinkScreen> createState() => _OneTimeLinkScreenState();
}

class _OneTimeLinkScreenState extends State<OneTimeLinkScreen> {
  late final OneTimeLinkService _service =
      widget._service ?? OneTimeLinkService();
  final _secret = TextEditingController();
  final _pass = TextEditingController();
  bool _usePass = false;
  bool _busy = false;
  String? _link;
  bool _failed = false;

  @override
  void dispose() {
    _secret.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
      _link = null;
    });
    try {
      final link = await _service.createLink(
        secret,
        passphrase: _usePass ? _pass.text : null,
      );
      if (mounted) setState(() => _link = link);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final palette = context.veilPalette;
    return VeilShell(
      title: l10n.oneTimeLinkTitle,
      child: ListView(
        children: [
          Text(
            l10n.oneTimeLinkIntro,
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: VeilSpace.md),
          TextField(
            controller: _secret,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.oneTimeLinkSecretLabel,
              hintText: l10n.oneTimeLinkSecretHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: VeilSpace.xs),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _usePass,
            onChanged: _busy ? null : (v) => setState(() => _usePass = v ?? false),
            title: Text(l10n.oneTimeLinkUsePassphrase, style: theme.textTheme.bodyMedium),
          ),
          if (_usePass)
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.oneTimeLinkPassphraseLabel),
            ),
          const SizedBox(height: VeilSpace.md),
          FilledButton(
            onPressed: _busy ? null : _generate,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.oneTimeLinkCreate),
          ),
          const SizedBox(height: VeilSpace.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(label: l10n.oneTimeLinkPillEncrypted),
              VeilStatusPill(label: l10n.oneTimeLinkPillServerBlind),
              VeilStatusPill(label: l10n.oneTimeLinkPillBurns),
            ],
          ),
          if (_failed) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(message: l10n.oneTimeLinkFailed, tone: VeilBannerTone.danger),
          ],
          if (_link != null) ...[
            const SizedBox(height: VeilSpace.xl),
            Center(
              child: QrImageView(
                data: _link!,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: VeilSpace.md),
            SelectableText(_link!, style: theme.textTheme.bodySmall),
            const SizedBox(height: VeilSpace.xs),
            VeilButton(
              tone: VeilButtonTone.secondary,
              icon: Icons.copy,
              label: l10n.oneTimeLinkCopy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _link!));
                if (context.mounted) {
                  VeilToast.show(context, message: l10n.oneTimeLinkCopied);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
