import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../session/session.dart';
import '../platform/app_env.dart';
import '../theme/app_theme.dart';
import '../widgets/debug_badge.dart';
import '../widgets/message_bubble.dart';
import '../widgets/trust_dialog.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  int _lastMessageCount = 0;
  bool _attached = false;
  Session? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
    _inputController.addListener(_onInputChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_attached) return;
    _attached = true;
    _session = context.read<Session>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session?.setChatVisible(true);
      _session?.notifyRead();
    });
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _session?.setChatVisible(false);
    super.dispose();
  }

  void _onInputChanged() {
    if (!mounted) return;
    setState(() {});
    if (_inputController.text.trim().isNotEmpty) {
      _session?.notifyTyping();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    final session = context.read<Session>();
    if (session.peerQid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没和对方握手完成')),
      );
      return;
    }
    session.sendMessage(text);
    _inputController.clear();
    _inputFocus.requestFocus();
    session.stopTyping();
  }

  Future<void> _confirmClearHistory() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除聊天记录？'),
        content: const Text(
          '只删除本机保存的消息，对方的记录不受影响。\n'
          '本地记录默认只保留最近 30 天。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<Session>().clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('聊天记录已清除')),
    );
  }

  Future<void> _confirmClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('结束这次会话？'),
        content: const Text(
          '连接将断开。聊天记录已保存在本机，可以从联系人列表再次打开。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<Session>().close();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_lastMessageCount != session.messages.length) {
      _lastMessageCount = session.messages.length;
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '返回联系人',
          onPressed: _confirmClose,
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 4,
        title: Row(
          children: [
            _PeerAvatar(
              verified: session.peerVerified,
              online: session.peerStatus == PeerStatus.online,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    session.peerDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  _StatusLine(session: session),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: session.peerVerified ? '身份已核对' : '核对安全码',
            onPressed: () => showTrustDialog(context, session),
            icon: Icon(
              session.peerVerified
                  ? Icons.verified_user
                  : Icons.gpp_maybe_outlined,
              color: session.peerVerified
                  ? context.palette.success
                  : context.palette.warning,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
            onSelected: (value) {
              switch (value) {
                case 'link':
                  _showMyInvite(session);
                case 'trust':
                  showTrustDialog(context, session);
                case 'clear':
                  _confirmClearHistory();
                case 'close':
                  _confirmClose();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'link',
                child: Row(
                  children: [
                    Icon(Icons.link_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('我的邀请链接'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'trust',
                child: Row(
                  children: [
                    Icon(Icons.gpp_good_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('核对安全码'),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear',
                child: _ClearHistoryItem(),
              ),
              PopupMenuItem(
                value: 'close',
                child: Row(
                  children: [
                    Icon(Icons.power_settings_new_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('结束会话'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (session.isDebug) _DebugStrip(env: session.env),
            if (session.phase == SessionPhase.reconnecting)
              const _ReconnectBanner(),
            if (!session.peerVerified)
              _TrustBanner(onTap: () => showTrustDialog(context, session)),
            Expanded(
              child: session.messages.isEmpty
                  ? _EmptyState(
                      verified: session.peerVerified,
                      onVerify: () => showTrustDialog(context, session),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Scrollbar(
                          controller: _scrollController,
                          child: ListView.builder(
                            controller: _scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding:
                                const EdgeInsets.fromLTRB(20, 12, 20, 12),
                            itemCount: session.messages.length,
                            itemBuilder: (_, i) {
                              final message = session.messages[i];
                              return MessageBubble(
                                message: message,
                                showTime:
                                    _shouldShowTime(session.messages, i),
                                onRetry: message.mid == null
                                    ? null
                                    : () =>
                                        session.retryMessage(message.mid!),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
            ),
            if (session.peerTyping)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: const _TypingIndicator(),
                ),
              ),
            _InputBar(
              controller: _inputController,
              focusNode: _inputFocus,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowTime(List<ChatMessage> list, int i) {
    if (i == 0) return true;
    return list[i].time.difference(list[i - 1].time).inMinutes >= 5;
  }

  void _showMyInvite(Session session) {
    final link = session.myInviteLink;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final messenger = ScaffoldMessenger.of(ctx);
        return AlertDialog(
          title: const Text('我的邀请链接'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '如果对方还没订阅你，把这条链接发给他：',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                if (link.isNotEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: link,
                        size: 150,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.L,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SelectableText(
                  link,
                  style: monoStyle(ctx, fontSize: 11.5, letterSpacing: 0),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: link.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('邀请链接已复制')),
                      );
                    },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

// ====================================================================
// 顶部状态
// ====================================================================

class _ClearHistoryItem extends StatelessWidget {
  const _ClearHistoryItem();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.delete_outline, size: 18, color: scheme.error),
        const SizedBox(width: 10),
        Text(
          '清除聊天记录',
          style: TextStyle(color: scheme.error),
        ),
      ],
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  final bool verified;
  final bool online;

  const _PeerAvatar({required this.verified, required this.online});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: verified
                ? palette.successContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            verified ? Icons.shield_outlined : Icons.lock_person_outlined,
            size: 21,
            color:
                verified ? palette.onSuccessContainer : scheme.onSurfaceVariant,
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online ? palette.success : scheme.outline,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final Session session;

  const _StatusLine({required this.session});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;

    String label;
    Color color;
    var breathing = false;

    if (session.phase == SessionPhase.reconnecting) {
      label = '连接断开，正在重连…';
      color = palette.warning;
      breathing = true;
    } else if (session.peerTyping) {
      label = '正在输入…';
      color = palette.success;
    } else if (session.peerActivity != null) {
      label = session.peerActivity!;
      color = scheme.primary;
    } else {
      switch (session.peerStatus) {
        case PeerStatus.online:
          label = session.peerVerified ? '在线 · 已核实' : '在线 · 端到端加密';
          color = palette.success;
        case PeerStatus.waiting:
          label = '等待对方接入';
          color = palette.warning;
          breathing = true;
        case PeerStatus.offline:
          label = '对方离线 · 消息会暂存';
          color = palette.warning;
        case PeerStatus.unknown:
          label = '连接中…';
          color = scheme.outline;
      }
    }

    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Row(
      children: [
        breathing ? _Breathing(child: dot) : dot,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _Breathing extends StatefulWidget {
  final Widget child;

  const _Breathing({required this.child});

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

// ====================================================================
// 信任 / 调试 / 重连提示条
// ====================================================================

class _TrustBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _TrustBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Color.alphaBlend(
        palette.warning.withValues(alpha: 0.08),
        scheme.surface,
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: palette.warning, width: 3),
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 8, 10, 8),
          child: Row(
            children: [
              Icon(
                Icons.gpp_maybe_outlined,
                size: 17,
                color: palette.warning,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '身份尚未核对 · 建议比对 6 位安全码',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '去核对',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugStrip extends StatelessWidget {
  final AppEnv env;

  const _DebugStrip({required this.env});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
      child: Row(
        children: [
          DebugBadge(env: env),
          const Spacer(),
          Text(
            '同机 A/B 测试',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.2,
              color: scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '连接已断开，正在自动重连…',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// 空状态 / 输入中
// ====================================================================

class _EmptyState extends StatelessWidget {
  final bool verified;
  final VoidCallback onVerify;

  const _EmptyState({required this.verified, required this.onVerify});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: (verified ? palette.success : scheme.primary)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  verified ? Icons.verified_user_outlined : Icons.lock_outline,
                  size: 30,
                  color: verified ? palette.success : scheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                verified ? '身份已核对' : '端到端加密已建立',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                verified
                    ? '这条通道的密钥只存在于你们两台设备上。'
                    : '服务器只能看到密文。建议先与对方核对 6 位安全码，确认没有中间人。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              if (!verified)
                OutlinedButton.icon(
                  onPressed: onVerify,
                  icon: const Icon(Icons.gpp_good_outlined, size: 18),
                  label: const Text('核对安全码'),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: palette.success),
                    const SizedBox(width: 5),
                    Text(
                      '可以开始说话了',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.success,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '对方正在输入',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: _Dot(controller: _controller, index: i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final AnimationController controller;
  final int index;

  const _Dot({required this.controller, required this.index});

  @override
  Widget build(BuildContext context) {
    final start = index * 0.18;
    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.25, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.25), weight: 1),
    ]).animate(CurvedAnimation(
      parent: controller,
      curve: Interval(start, math.min(1.0, start + 0.55)),
    ));

    return FadeTransition(
      opacity: opacity,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ====================================================================
// 输入栏
// ====================================================================

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSend = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: '输入消息，仅对方可读',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: scheme.outline,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: scheme.primary,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SendButton(enabled: canSend, onTap: onSend),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = enabled ? scheme.onPrimary : scheme.outline;

    return Tooltip(
      message: '发送',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Icon(Icons.arrow_upward, color: fg),
          ),
        ),
      ),
    );
  }
}
