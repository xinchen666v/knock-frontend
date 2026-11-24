import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session/session.dart';
import '../theme/app_theme.dart';

Future<void> showTrustDialog(BuildContext context, Session session) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TrustDialog(session: session),
  );
}

class _TrustDialog extends StatefulWidget {
  final Session session;

  const _TrustDialog({required this.session});

  @override
  State<_TrustDialog> createState() => _TrustDialogState();
}

class _TrustDialogState extends State<_TrustDialog> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.palette;
    final session = widget.session;
    final code = session.sasCode;
    final mine = session.myFingerprint;
    final peer = session.peerFingerprint;
    final verified = session.peerVerified;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: verified
                  ? palette.successContainer
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              verified ? Icons.verified_user_outlined : Icons.shield_outlined,
              size: 22,
              color: verified
                  ? palette.onSuccessContainer
                  : scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('核对安全码')),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '请通过面对面、电话或其他可信渠道，与对方比对下面这 6 位数字。'
                '一致，说明这条通道没有中间人。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (verified) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: palette.successContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: palette.onSuccessContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '双方已核对，指纹已保存在本机',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.onSuccessContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SasCard(code: code),
              const SizedBox(height: 18),
              if (mine != null)
                _FingerprintRow(
                  label: '我的指纹',
                  value: mine,
                ),
              if (peer != null) ...[
                const SizedBox(height: 10),
                _FingerprintRow(
                  label: '对方指纹',
                  value: peer,
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '指纹来自邀请链接；安全码由双方公钥共同计算。'
                        '如果链接被调包，两端屏幕上的数字会不同。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: verified
          ? [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ]
          : [
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('稍后再说'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _saving || code == null ? null : _verify,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('数字一致，标记为可信'),
              ),
            ],
    );
  }

  Future<void> _verify() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    await widget.session.markPeerVerified();
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('已标记为可信，之后可随时在对话页查看')),
    );
  }
}

class _SasCard extends StatelessWidget {
  final String? code;

  const _SasCard({required this.code});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = (code ?? '').split('-');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '安全码',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '复制安全码',
                onPressed: code == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: code!));
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(content: Text('安全码已复制')),
                        );
                      },
                icon: Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          if (code == null || parts.length != 2)
            Text(
              '安全码尚未生成',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CodeBox(value: parts[0]),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 24,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                _CodeBox(value: parts[1]),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            '两端显示的数字必须完全一致',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  final String value;

  const _CodeBox({required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Consolas', 'Menlo', 'Courier New'],
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: 4,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _FingerprintRow extends StatelessWidget {
  final String label;
  final String value;

  const _FingerprintRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grouped = _group(value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.fingerprint, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
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
            tooltip: '复制$label',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text('$label已复制')),
              );
            },
            icon: Icon(Icons.copy_outlined, size: 16, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  String _group(String fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(
        fingerprint.substring(i, (i + 4).clamp(0, fingerprint.length)),
      );
    }
    return buffer.toString();
  }
}
