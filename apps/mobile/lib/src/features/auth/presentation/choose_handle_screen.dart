import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

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

    return VeilShell(
      title: 'Choose Handle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Handles are the discovery layer. Phone numbers stay out.'),
          const SizedBox(height: 24),
          TextField(
            controller: _handleController,
            enabled: !_submitting,
            decoration: const InputDecoration(labelText: 'Handle', hintText: 'cold.operator'),
          ),
          const SizedBox(height: 12),
          const Text('Lowercase. Minimal. Permanent enough to matter.'),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              session.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Spacer(),
          FilledButton(
            onPressed: _submitting
                ? null
                : () async {
                    setState(() => _submitting = true);
                    try {
                      await ref.read(appSessionProvider.notifier).registerAndAuthenticate(
                            handle: _handleController.text.trim(),
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
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(_submitting ? 'Binding device...' : 'Bind device'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
