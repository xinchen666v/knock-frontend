import 'package:flutter/material.dart';

import '../platform/app_env.dart';
import '../theme/app_theme.dart';

class DebugBadge extends StatelessWidget {
  final AppEnv env;

  const DebugBadge({super.key, required this.env});

  @override
  Widget build(BuildContext context) {
    if (!env.isDebug) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;

    return Tooltip(
      message: '调试身份：${env.identityPath}\n服务器：${env.server ?? '默认'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showDetails(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 13,
                color: palette.warning,
              ),
              const SizedBox(width: 5),
              Text(
                '调试 · ${env.debugLabel}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调试模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前进程使用独立的身份与状态文件，两个实例互不覆盖。'),
            const SizedBox(height: 16),
            _InfoRow(label: '身份文件', value: env.identityPath ?? '未设置'),
            const SizedBox(height: 10),
            _InfoRow(label: '服务器', value: env.server ?? '默认'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(value, style: monoStyle(context, fontSize: 12)),
      ],
    );
  }
}
