import 'package:flutter/material.dart';

import '../session/session.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showTime;

  const MessageBubble({
    super.key,
    required this.message,
    required this.showTime,
  });

  @override
  Widget build(BuildContext context) {
    // key 用 mid（或时间+内容）保证每条消息只播一次进入动画
    final bubbleKey = message.mid ??
        '${message.time.microsecondsSinceEpoch}_${message.text.hashCode}';

    return _EnterAnimated(
      key: ValueKey(bubbleKey),
      child: _BubbleBody(message: message, showTime: showTime),
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

/// 气泡主体：时间分隔 + 气泡 + 失败提示
class _BubbleBody extends StatelessWidget {
  final ChatMessage message;
  final bool showTime;

  const _BubbleBody({required this.message, required this.showTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMine = message.isMine;

    final bubbleColor = isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = isMine
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTime) _TimeDivider(time: message.time),
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.68,
              ),
              child: Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 18),
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
                  if (message.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 12,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '对方离线，消息未送达',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
        child: Text(
          _formatTime(time),
          style: TextStyle(
            fontSize: 11,
            color: scheme.outline,
            letterSpacing: 0.5,
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