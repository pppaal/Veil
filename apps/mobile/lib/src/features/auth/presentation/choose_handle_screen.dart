import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class ChooseHandleScreen extends ConsumerStatefulWidget {
  const ChooseHandleScreen({super.key});

  @override
  ConsumerState<ChooseHandleScreen> createState() => _ChooseHandleScreenState();
}

class _ChooseHandleScreenState extends ConsumerState<ChooseHandleScreen> {
  final _handleController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final displayName = GoRouterState.of(context).extra as String?;
    final handle = _handleController.text.trim();

    return VeilShell(
      title: 'Choose Handle',
      child: ListView(
        children: [
          const VeilHeroPanel(
            eyebrow: 'HANDLE REGISTRATION',
            title: 'Phone numbers stay out.',
            body:
                'Pick a direct handle for discovery. VEIL binds the handle to this device after local identity material is generated.',
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilSectionLabel('HANDLE'),
                const SizedBox(height: VeilSpace.sm),
                TextField(
                  controller: _handleController,
                  enabled: !_submitting,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Handle',
                    hintText: 'cold.operator',
                    prefixText: '@',
                  ),
                ),
                const SizedBox(height: VeilSpace.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    VeilStatusPill(
                      label: handle.isEmpty ? 'Choose a handle' : '@$handle',
                      tone: handle.isEmpty ? VeilBannerTone.warn : VeilBannerTone.info,
                    ),
                    const VeilStatusPill(label: 'No contact sync'),
                    const VeilStatusPill(label: 'Device-bound'),
                  ],
                ),
                const SizedBox(height: VeilSpace.sm),
                Text(
                  'Lowercase. Minimal. Permanent enough to matter.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilSectionLabel('BINDING FLOW'),
                const SizedBox(height: VeilSpace.md),
                  VeilStepRow(
                    step: 1,
                    title: 'Generate local identity',
                    body: 'Create device-bound material and keep the private side on this device.',
                    active: session.authFlowStage == AuthFlowStage.generatingKeys,
                    complete: session.authFlowStage.index > AuthFlowStage.generatingKeys.index,
                  ),
                  const SizedBox(height: VeilSpace.sm),
                  VeilStepRow(
                    step: 2,
                    title: 'Register handle',
                    body: 'Publish only public device material and handle metadata.',
                    active: session.authFlowStage == AuthFlowStage.registering,
                    complete: session.authFlowStage.index > AuthFlowStage.registering.index,
                  ),
                  const SizedBox(height: VeilSpace.sm),
                  VeilStepRow(
                    step: 3,
                    title: 'Challenge device',
                    body: 'Request a short-lived server challenge for this registered device.',
                    active: session.authFlowStage == AuthFlowStage.requestingChallenge,
                    complete: session.authFlowStage.index >
                        AuthFlowStage.requestingChallenge.index,
                  ),
                  const SizedBox(height: VeilSpace.sm),
                  VeilStepRow(
                    step: 4,
                    title: 'Verify and bind',
                    body: 'Complete verification and activate the device session.',
                    active: session.authFlowStage == AuthFlowStage.verifying,
                    complete: session.authFlowStage == AuthFlowStage.complete,
                  ),
              ],
            ),
          ),
          if (session.errorMessage != null) ...[
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: 'Binding failed',
              message: session.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.xl),
          FilledButton(
            onPressed: _submitting || handle.isEmpty
                ? null
                : () async {
                    setState(() => _submitting = true);
                    try {
                      await ref.read(appSessionProvider.notifier).registerAndAuthenticate(
                            handle: handle,
                            displayName: displayName?.isEmpty ?? true ? null : displayName,
                          );
                      if (context.mounted && ref.read(appSessionProvider).isAuthenticated) {
                        context.go('/conversations');
                      }
                    } catch (_) {
                    } finally {
                      if (mounted) {
                        setState(() => _submitting = false);
                      }
                    }
                  },
            child: Text(_ctaLabelFor(session)),
          ),
        ],
      ),
    );
  }

  String _ctaLabelFor(AppSessionState session) {
    if (_submitting || session.isAuthenticating) {
      return session.authFlowStage.label;
    }
    return 'Bind this device';
  }
}
