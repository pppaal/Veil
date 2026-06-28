import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  String? _error;

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
      _error = null;
      _link = null;
    });
    try {
      final link = await _service.createLink(
        secret,
        passphrase: _usePass ? _pass.text : null,
      );
      if (mounted) setState(() => _link = link);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '링크 생성에 실패했습니다. 잠시 후 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('일회성 비밀 링크')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '한 번 읽히면 사라지는 메시지를 만듭니다. 받는 사람은 앱이 없어도 됩니다. '
            '복호화 키는 링크에만 담겨 서버로 전송되지 않습니다.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _secret,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '비밀 내용',
              hintText: '비밀번호, 계좌, 민감한 메모…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _usePass,
            onChanged: _busy ? null : (v) => setState(() => _usePass = v ?? false),
            title: const Text('암호문구 추가 (링크에 키를 넣지 않음 — 더 안전)'),
          ),
          if (_usePass)
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '암호문구',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _generate,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('보안 링크 생성'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_link != null) ...[
            const SizedBox(height: 24),
            Center(
              child: QrImageView(
                data: _link!,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(_link!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _link!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('링크를 복사했습니다')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('링크 복사'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '🔒 종단간 암호화 · 🙈 서버는 평문·키를 못 봄 · 💨 읽으면 소멸',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
