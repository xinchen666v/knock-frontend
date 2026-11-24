import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../session/session.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showTime;
  final VoidCallback? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    required this.showTime,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // key 用 mid（或时间+内容）保证每条消息只播一次进入动画
    final bubbleKey = message.mid ??
        '${message.time.microsecondsSinceEpoch}_${message.text.hashCode}';

    return _EnterAnimated(
      key: ValueKey(bubbleKey),
      child: message.isSystem
          ? _SystemNotice(message: message, showTime: showTime)
          : _BubbleBody(
              message: message,
              showTime: showTime,
              onRetry: onRetry,
            ),
    );
  }
}

/// 单条消息的进入动画：淡入 + 从下方滑入
class _EnterAnimated extends StatefulWidget {
  final Widget child;

  const _EnterAnimated({super.key, required this.child});

  @override
  State<_EnterAnimated> createState() => _EnterAnimatedState();
}

class _EnterAnimatedState extends State<_EnterAnimated>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// 气泡主体：时间分隔 + 气泡 + 送达状态
class _BubbleBody extends StatelessWidget {
  final ChatMessage message;
  final bool showTime;
  final VoidCallback? onRetry;

  const _BubbleBody({
    required this.message,
    required this.showTime,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final isMine = message.isMine;
    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.72, 520.0);

    final bubbleColor = isMine ? scheme.primaryContainer : palette.peerBubble;
    final textColor = isMine ? scheme.onPrimaryContainer : palette.onPeerBubble;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTime) _TimeDivider(time: message.time),
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      border: isMine
                          ? null
                          : Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.45),
                            ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 6),
                        bottomRight: Radius.circular(isMine ? 6 : 18),
                      ),
                    ),
                    child: SelectableText(
                      message.text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(height: 3),
                  _StatusRow(message: message, onRetry: onRetry),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;

  const _StatusRow({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final time = _hhmm(message.time);

    if (message.failed) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 13, color: scheme.error),
              const SizedBox(width: 4),
              Text(
                '未送达 · 点击重试',
                style: TextStyle(fontSize: 10.5, color: scheme.error),
              ),
            ],
          ),
        ),
      );
    }

    final (icon, label, color) = switch (message.status) {
      MessageStatus.sending => (
          Icons.schedule,
          '发送中',
          scheme.outline,
        ),
      MessageStatus.sent => (
          Icons.done,
          '已送达',
          scheme.outline,
        ),
      MessageStatus.read => (
          Icons.done_all,
          '已读',
          palette.success,
        ),
      MessageStatus.failed => (
          Icons.error_outline,
          '发送失败',
          scheme.error,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: TextStyle(fontSize: 10.5, color: scheme.outline),
          ),
          const SizedBox(width: 5),
          Tooltip(
            message: label,
            child: Icon(icon, size: 13, color: color),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 系统提示：居中、低噪音
class _SystemNotice extends StatelessWidget {
  final ChatMessage message;
  final bool showTime;

  const _SystemNotice({required this.message, required this.showTime});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          if (showTime) _TimeDivider(time: message.time),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: palette.systemBubble,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: palette.onSystemBubble,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间分隔符：居中、淡色、小巧
class _TimeDivider extends StatelessWidget {
  final DateTime time;

  const _TimeDivider({required this.time});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _formatTime(time),
            style: TextStyle(
              fontSize: 10.5,
              color: scheme.outline,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        now.year == t.year && now.month == t.month && now.day == t.day;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (sameDay) return hm;
    return '${t.month}月${t.day}日 $hm';
  }
}
