import 'package:flutter/material.dart';

import 'invite_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _onJoin(BuildContext context) async {
    final link = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinDialog(),
    );
    if (link == null || link.trim().isEmpty) return;
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InvitePage(joinLink: link.trim()),
    ));
  }

  void _onCreate(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const InvitePage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.door_front_door_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'knock',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w300,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '说点私密的，不留痕',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 64),
                  FilledButton.tonal(
                    onPressed: () => _onCreate(context),
                    child: const Text('创建一扇门'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _onJoin(context),
                    child: const Text('我有邀请链接'),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'v0.1 · knock protocol',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴对方的邀请链接'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          hintText: 'knock://...',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('连接'),
        ),
      ],
    );
  }
}