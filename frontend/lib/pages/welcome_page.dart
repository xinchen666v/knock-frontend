import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../session/session.dart';
import 'invite_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState  extends State<WelcomePage> {
  bool _busy = false;

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

    /// 隐藏入口：长按 logo 重置身份
  Future<void> _onResetIdentity(BuildContext context) async {
    if (_busy) return;
    final session = context.read<Session>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置身份？'),
        content: const Text(
          '当前的邀请链接将作废，之后会生成一扇新的门。\n\n'
          '对方手里的旧链接将无法再联系到你，'
          '需要把你重新分享新的邀请链接。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    await session.resetIdentity();
    if (!mounted) return;
    // 导航到创建流程——createSession 发现 prefs 里没有 qid，自动 NEW
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const InvitePage(),
    ));
    setState(() => _busy = false);
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
                  // ★ logo 包上 GestureDetector，长按触发重置
                  GestureDetector(
                    onLongPress: () => _onResetIdentity(context),
                    child: const Icon(
                      Icons.door_front_door_outlined,
                      size: 72,
                      color: Color(0xFF4A6FA5),
                    ),
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