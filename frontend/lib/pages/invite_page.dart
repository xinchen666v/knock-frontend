import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../session/session.dart';
import '../theme/app_theme.dart';
import '../widgets/debug_badge.dart';
import 'chat_page.dart';

class InvitePage extends StatefulWidget {
  /// 传入 joinLink 表示“我有邀请链接”的加入模式。
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

  @override
  void dispose() {
    _peerController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_didInit) return;
    _didInit = true;
    final session = context.read<Session>();

    if (widget.joinLink != null) {
      await _join(session, widget.joinLink!);
    } else {
      setState(() => _busy = true);
      await session.createSession();
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _join(Session session, String link) async {
    setState(() => _busy = true);
    final ok = await session.subscribeToPeer(link);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _snack(session.errorMessage ?? '订阅失败');
      return;
    }
    _goToChat();
  }

  Future<void> _onConnect() async {
    final link = _peerController.text.trim();
    if (link.isEmpty) return;
    await _join(context.read<Session>(), link);
  }

  Future<void> _onRetry() async {
    final session = context.read<Session>();
    final link = widget.joinLink ?? _peerController.text.trim();
    if (link.isNotEmpty) {
      await _join(session, link);
      return;
    }
    setState(() => _busy = true);
    await session.createSession();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  void _goToChat() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);

    if (session.phase == SessionPhase.chatting &&
        session.messages.isNotEmpty &&
        ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToChat());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.joinLink == null ? '分享邀请' : '连接对方'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: DebugBadge(env: session.env)),
          ),
        ],
      ),
      body: switch (session.phase) {
        SessionPhase.failed => _ErrorState(
            message: session.errorMessage ?? '连接失败',
            busy: _busy,
            onRetry: _onRetry,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        SessionPhase.waitingForPeer => _InviteContent(
            session: session,
            busy: _busy,
            controller: _peerController,
            onConnect: _onConnect,
          ),
        SessionPhase.chatting => const Center(
            child: CircularProgressIndicator(),
          ),
        _ => _ConnectingState(
            joinMode: widget.joinLink != null,
            busy: _busy,
          ),
      },
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

// ====================================================================
// 等待对方 / 分享内容
// ====================================================================

class _InviteContent extends StatelessWidget {
  final Session session;
  final bool busy;
  final TextEditingController controller;
  final VoidCallback onConnect;

  const _InviteContent({
    required this.session,
    required this.busy,
    required this.controller,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final link = session.myInviteLink;
    final fingerprint = session.myFingerprint;

    return Stack(
      children: [
        const Positioned.fill(child: _InviteGlow()),
        SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.door_front_door_outlined,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '门已经打开',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '把这条邀请发给对方，对方粘贴后即可建立加密会话。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _QrCard(link: link),
                    const SizedBox(height: 14),
                    if (fingerprint != null)
                      _FingerprintCard(
                        fingerprint: fingerprint,
                        onCopy: () async {
                          await Clipboard.setData(
                            ClipboardData(text: fingerprint),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('身份指纹已复制')),
                          );
                        },
                      ),
                    const SizedBox(height: 14),
                    _LinkCard(link: link),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: link.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: link),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('邀请链接已复制')),
                              );
                            },
                      icon: const Icon(Icons.copy_outlined, size: 19),
                      label: const Text('复制邀请链接'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: scheme.outline,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '链接里包含你的公钥，请只发给想联系的人',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const _OrDivider(),
                    const SizedBox(height: 22),
                    _JoinCard(
                      controller: controller,
                      busy: busy,
                      onConnect: onConnect,
                    ),
                    const SizedBox(height: 28),
                    const _WaitingHint(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QrCard extends StatelessWidget {
  final String link;

  const _QrCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: link.isEmpty
            ? const SizedBox(
                width: 188,
                height: 188,
                child: Center(child: CircularProgressIndicator()),
              )
            : QrImageView(
                data: link,
                size: 188,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.L,
                semanticsLabel: '邀请二维码',
              ),
      ),
    );
  }
}

class _FingerprintCard extends StatelessWidget {
  final String fingerprint;
  final VoidCallback onCopy;

  const _FingerprintCard({required this.fingerprint, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grouped = _group(fingerprint);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.fingerprint, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的身份指纹',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  grouped,
                  style: monoStyle(
                    context,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制指纹',
            onPressed: onCopy,
            icon: Icon(Icons.copy_outlined, size: 17, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  String _group(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(value.substring(i, (i + 4).clamp(0, value.length)));
    }
    return buffer.toString();
  }
}

class _LinkCard extends StatelessWidget {
  final String link;

  const _LinkCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '邀请链接',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            link.isEmpty ? '正在生成…' : link,
            style: monoStyle(
              context,
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: scheme.onSurface,
            ).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConnect;

  const _JoinCard({
    required this.controller,
    required this.busy,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('对方也发来了链接？', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '粘贴对方的邀请，订阅他的队列，就能互发加密消息。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          enabled: !busy,
          style: monoStyle(context, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'knock://…',
            hintStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: scheme.outline,
            ),
            prefixIcon: const Icon(Icons.link, size: 20),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: busy ? null : onConnect,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('连接并开始聊天'),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '或者',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _WaitingHint extends StatelessWidget {
  const _WaitingHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const _BreathingDot(),
        const SizedBox(height: 8),
        Text(
          '对方接入并发送消息后，会自动进入聊天',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ====================================================================
// 连接中 / 失败
// ====================================================================

class _ConnectingState extends StatelessWidget {
  final bool joinMode;
  final bool busy;

  const _ConnectingState({required this.joinMode, required this.busy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.lock_clock_outlined,
                size: 30,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              joinMode ? '正在建立加密会话' : '正在创建你的门',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              joinMode ? '校验链接、订阅对方队列…' : '生成身份密钥、向服务器申请队列…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            if (!busy) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ErrorState({
    required this.message,
    required this.busy,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.link_off,
                  size: 28,
                  color: scheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text('连接失败', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : onRetry,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('重试'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onBack, child: const Text('返回')),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteGlow extends StatelessWidget {
  const _InviteGlow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: -160,
          right: -120,
          child: _Glow(
            size: 320,
            color: scheme.primary.withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          bottom: -180,
          left: -140,
          child: _Glow(
            size: 360,
            color: scheme.tertiary.withValues(alpha: 0.07),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

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
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '等待对方接入…',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
