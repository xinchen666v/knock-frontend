import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../session/session.dart';
import 'chat_page.dart';

class InvitePage extends StatefulWidget {
  /// 如果传入 joinLink，说明是"我有邀请链接"进入的加入模式
  final String? joinLink;

  const InvitePage({super.key, this.joinLink});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  final _peerController = TextEditingController();
  bool _didInit = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (_didInit) return;
    _didInit = true;

    final session = context.read<Session>();

    // 无论哪种模式，都先建自己的队列
    final ok = await session.createSession();
    if (!ok || !mounted) return;

    // 加入模式：已经拿到对方链接，自动订阅
    if (widget.joinLink != null) {
      setState(() => _busy = true);
      final subOk = await session.subscribeToPeer(widget.joinLink!);
      if (!mounted) return;
      setState(() => _busy = false);
      if (subOk) {
        _goToChat();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(session.errorMessage ?? '订阅失败')),
        );
      }
    }
  }

  Future<void> _onConnect() async {
    final link = _peerController.text.trim();
    if (link.isEmpty) return;

    setState(() => _busy = true);
    final session = context.read<Session>();
    final ok = await session.subscribeToPeer(link);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.errorMessage ?? '订阅失败')),
      );
      return;
    }
    _goToChat();
  }

  void _goToChat() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
  }

  @override
  void dispose() {
    _peerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);

    // 对方主动发来消息时自动进聊天页
    if (session.phase == SessionPhase.chatting &&
        session.messages.isNotEmpty &&
        ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToChat());
    }

    if (session.phase == SessionPhase.failed) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  session.errorMessage ?? '连接失败',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (session.phase != SessionPhase.waitingForPeer) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final inviteLink = session.myInviteLink;

    return Scaffold(
      appBar: AppBar(title: const Text('等待敲门')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '门已经打开，把钥匙给对方',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // 二维码
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: inviteLink,
                        size: 180,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 链接文本
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      inviteLink,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: inviteLink));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制邀请链接'),
                  ),

                  const SizedBox(height: 32),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '或者',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text(
                    '如果对方把链接发给了你，粘贴到下面',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _peerController,
                    maxLines: 3,
                    minLines: 1,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      hintText: 'knock://...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _onConnect,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('连接'),
                  ),

                  const SizedBox(height: 32),
                  const _BreathingDot(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 呼吸灯：等待对端接入时的心跳感
class _BreathingDot extends StatefulWidget {
  const _BreathingDot();

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.25, end: 1.0).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '等待对方接入...',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}