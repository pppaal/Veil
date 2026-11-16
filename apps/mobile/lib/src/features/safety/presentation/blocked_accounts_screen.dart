import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/presentation/peer_names.dart';
import '../application/safety_accounts.dart';
import '../data/blocked_accounts.dart';
import '../data/safety_providers.dart';
import 'block_actions.dart';

/// The accounts the user blocked, newest first, each with its name (where
/// this phone knows one), its handle and Unblock. Opened from Settings.
class BlockedAccountsScreen extends ConsumerStatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  ConsumerState<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends ConsumerState<BlockedAccountsScreen> {
  @override
  void initState() {
    super.initState();
    // Read again on every visit: a block made on another device shows here.
    Future.microtask(() {
      if (mounted) ref.read(blockedAccountsProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocked = ref.watch(blockedAccountsProvider);
    // The names are the nicknames on this phone: shown as they load.
    ref.watch(peerNamesProvider);
    final accounts = ref.read(safetyAccountsProvider);

    final Widget body;
    if (blocked.accounts.isEmpty && !blocked.loaded) {
      body = blocked.loadFailed && !blocked.isLoading
          ? VeilEmptyState(
              title: l10n.blockedAccountsLoadFailedTitle,
              action: VeilButton(
                expanded: false,
                tone: VeilButtonTone.secondary,
                label: l10n.commonRetry,
                onPressed: blocked.refresh,
              ),
            )
          : const Center(
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            );
    } else if (blocked.accounts.isEmpty) {
      // One quiet line at the top of the list, as Signal's "No blocked
      // users": not centred, nothing else.
      body = ListView(
        padding: const EdgeInsets.fromLTRB(VeilSpace.md, VeilSpace.md, VeilSpace.md, VeilSpace.xxl),
        children: [
          Text(
            l10n.blockedAccountsEmptyTitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.veilPalette.textMuted),
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: VeilSpace.md, bottom: VeilSpace.xxl),
        children: [
          VeilGroup(
            inset: BlockedAccountRow.textInset,
            children: [
              for (final account in blocked.accounts)
                BlockedAccountRow(
                  key: ValueKey('blocked-${account.handle}'),
                  account: account,
                  name: accounts.knownNameFor(userId: account.userId, handle: account.handle),
                  onUnblock: () => unblockAccount(context, userId: account.userId, handle: account.handle),
                ),
            ],
          ),
        ],
      );
    }

    return VeilShell(title: l10n.blockedAccountsTitle, grouped: true, child: body);
  }
}

/// One blocked account: the avatar, the name this phone knows for it with
/// the @handle under it (or the @handle alone, never a bare handle, for one
/// with no name) and Unblock.
class BlockedAccountRow extends StatelessWidget {
  const BlockedAccountRow({super.key, required this.account, required this.name, required this.onUnblock});

  final BlockedAccount account;
  final String? name;
  final VoidCallback onUnblock;

  /// Where the text starts, and the hairlines between rows with it.
  static const double textInset = VeilSpace.md + 40 + VeilSpace.sm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = this.name;
    final handle = '@${account.handle}';
    return VeilRow(
      leading: VeilAvatar(name: name ?? account.handle, seed: account.handle),
      // A name and a handle are their owner's words: drawn as typed.
      title: name ?? handle,
      subtitle: name == null ? null : handle,
      trailing: TextButton(onPressed: onUnblock, child: Text(l10n.unblockAction)),
    );
  }
}

/// The Settings row that opens the blocked accounts, with how many there
/// are once there are any.
class BlockedAccountsSettingsRow extends ConsumerWidget {
  const BlockedAccountsSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(blockedAccountsProvider).accounts.length;
    return VeilRow(
      key: const ValueKey('settings-blocked-accounts'),
      title: l10n.blockedAccountsTitle,
      value: count > 0 ? '$count' : null,
      onTap: () => context.push('/blocked-accounts'),
    );
  }
}
