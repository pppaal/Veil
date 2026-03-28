import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/veil_shell.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VeilShell(
      title: 'Create Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This device becomes your identity.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text('If you lose this device, your account and messages are gone. This is intentional.'),
          const SizedBox(height: 28),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(labelText: 'Display name', hintText: 'Optional'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => context.go('/choose-handle', extra: _displayNameController.text.trim()),
            child: const SizedBox(width: double.infinity, child: Center(child: Text('Continue'))),
          ),
        ],
      ),
    );
  }
}
