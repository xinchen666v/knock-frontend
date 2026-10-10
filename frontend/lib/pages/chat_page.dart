import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../session/session.dart';
import '../widgets/message_bubble.dart';

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

  @override
  void initState() {
    super.initState();
    // 进入聊天页自动聚焦输入框，可以直接打字
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
    // 输入变化时刷新发送按钮的可用状态
    _inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
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
  }

  Future<void> _confirmClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('结束这次会话？'),
        // content: const Text('断开后，本次会话将不可恢复。'),
        content: const Text('连接将断开。你的邀请链接依然有效，重新打开 App 即可继续。'),
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
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<Session>().close();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    // 只在消息数量变化时滚到底部，避免每帧都触发
    if (_lastMessageCount != session.messages.length) {
      _lastMessageCount = session.messages.length;
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('对话', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            _StatusLine(status: session.peerStatus),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '我的邀请链接',
            icon: const Icon(Icons.link_outlined),
            onPressed: () => _showMyInvite(context, session),
          ),
          IconButton(
            tooltip: '结束会话',
            icon: const Icon(Icons.close),
            onPressed: _confirmClose,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: session.messages.isEmpty
                  ? const _EmptyHint()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: session.messages.length,
                      itemBuilder: (_, i) => MessageBubble(
                        message: session.messages[i],
                        showTime: _shouldShowTime(session.messages, i),
                      ),
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

  void _showMyInvite(BuildContext context, Session session) {
    final link = session.myInviteLink;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('我的邀请链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('如果对方还没订阅你，把这条链接发给他：',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            SelectableText(
              link,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制')),
              );
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 状态行：真正的圆点 + 文字，等待状态带呼吸效果
// ============================================================

class _StatusLine extends StatelessWidget {
  final PeerStatus status;
  const _StatusLine({required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      PeerStatus.online => const _StatusDot(
          label: '已连接',
          color: Color(0xFF4CAF50),
        ),
      PeerStatus.waiting => const _StatusDot(
          label: '等待对方接入',
          color: Color(0xFFFFB300),
          breathing: true,
        ),
      PeerStatus.offline => const _StatusDot(
          label: '对方已离线',
          color: Color(0xFFFF7043),
        ),
      PeerStatus.unknown => const _StatusDot(
          label: '未知',
          color: Colors.grey,
          hollow: true,
        ),
    };
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool breathing;
  final bool hollow;

  const _StatusDot({
    required this.label,
    required this.color,
    this.breathing = false,
    this.hollow = false,
  });

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: hollow ? Colors.transparent : color,
        border: hollow ? Border.all(color: color, width: 1.4) : null,
        shape: BoxShape.circle,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        breathing ? _Breathing(child: dot) : dot,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            letterSpacing: 0.2,
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

// ============================================================
// 空状态提示
// ============================================================

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.waving_hand_outlined,
              size: 44,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '说点什么吧',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '对方在等你',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 输入栏：带禁用态的发送按钮
// ============================================================

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
    final canSend = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
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
                hintText: '输入消息...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SendButton(enabled: canSend, onTap: onSend),
        ],
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

    return AnimatedContainer(
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
    );
  }
}