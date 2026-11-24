import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../contacts/contact.dart';
import '../platform/route_observer.dart';
import '../session/session.dart';
import '../theme/app_theme.dart';
import '../widgets/debug_badge.dart';
import 'invite_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with RouteAware {
  bool _busy = false;
  bool _contactsLoading = true;
  List<Contact> _contacts = const [];
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContacts());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (!mounted) return;
    final contacts = await context.read<Session>().loadContacts();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _contactsLoading = false;
    });
  }

  Future<void> _onCreate() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InvitePage()),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadContacts();
  }

  Future<void> _onJoin() async {
    if (_busy) return;
    final link = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinDialog(),
    );
    if (link == null || link.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InvitePage(joinLink: link.trim())),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadContacts();
  }

  Future<void> _onOpenContact(Contact contact) async {
    if (_busy) return;
    setState(() => _busy = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvitePage(joinLink: contact.inviteLink),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadContacts();
  }

  Future<void> _onRenameContact(Contact contact) async {
    final alias = await showDialog<String>(
      context: context,
      builder: (_) => _RenameContactDialog(contact: contact),
    );
    if (alias == null || !mounted) return;
    await context.read<Session>().renameContact(contact.fingerprint, alias);
    if (!mounted) return;
    await _loadContacts();
  }

  Future<void> _onDeleteContact(Contact contact) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除联系人？'),
        content: const Text(
          '会同时删除本机保存的聊天记录和“已核实”标记；对方不受影响。',
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await context.read<Session>().deleteContact(contact);
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadContacts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('联系人已删除')),
    );
  }

  Future<void> _onEditServer() async {
    if (_busy) return;
    final session = context.read<Session>();
    await showDialog<void>(
      context: context,
      builder: (_) => _ServerDialog(
        initial: session.effectiveServer,
        envServer: session.env.server,
      ),
    );
  }

  Future<void> _onResetIdentity() async {
    if (_busy) return;
    final session = context.read<Session>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置身份？'),
        content: const Text(
          '当前的邀请链接将作废，之后会生成一扇新的门。\n\n'
          '对方手里的旧链接将无法再联系到你，需要重新分享新的邀请链接。\n\n'
          '本地聊天记录不会被自动删除。',
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InvitePage()),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = context.watch<Session>();

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          DebugBadge(env: session.env),
                          const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: '更多',
                            icon: Icon(
                              Icons.more_horiz,
                              color: scheme.onSurfaceVariant,
                            ),
                            onSelected: (value) {
                              if (value == 'reset') _onResetIdentity();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'reset',
                                child: Row(
                                  children: [
                                    Icon(Icons.restart_alt, size: 18),
                                    SizedBox(width: 10),
                                    Text('重置身份'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      Center(child: _BrandMark(onLongPress: _onResetIdentity)),
                      const SizedBox(height: 24),
                      Text(
                        'knock',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '说点私密的，不留痕',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _FeaturePill(
                            icon: Icons.lock_outline,
                            label: '端到端加密',
                          ),
                          _FeaturePill(
                            icon: Icons.dns_outlined,
                            label: '服务器只见密文',
                          ),
                          _FeaturePill(
                            icon: Icons.fingerprint,
                            label: '可核对身份',
                          ),
                        ],
                      ),
                      const SizedBox(height: 44),
                      FilledButton.icon(
                        onPressed: _busy ? null : _onCreate,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        label: const Text('创建一扇门'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _onJoin,
                        icon: const Icon(Icons.key_outlined, size: 20),
                        label: const Text('我有邀请链接'),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Tooltip(
                          message: '修改创建新门使用的服务器',
                          child: TextButton.icon(
                            onPressed: _busy ? null : _onEditServer,
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(
                              Icons.dns_outlined,
                              size: 14,
                              color: scheme.outline,
                            ),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '服务器',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 11,
                                    color: scheme.outline,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  session.effectiveServer,
                                  style: monoStyle(
                                    context,
                                    fontSize: 11,
                                    letterSpacing: 0,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 12,
                                  color: scheme.outline,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      IgnorePointer(
                        ignoring: _busy,
                        child: _ContactsSection(
                          loading: _contactsLoading,
                          contacts: _contacts,
                          onOpen: _onOpenContact,
                          onRename: _onRenameContact,
                          onDelete: _onDeleteContact,
                        ),
                      ),
                      const SizedBox(height: 32),
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
                            '消息只在两台设备之间加密',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'knock v0.2 · protocol v2',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactsSection extends StatelessWidget {
  final bool loading;
  final List<Contact> contacts;
  final ValueChanged<Contact> onOpen;
  final ValueChanged<Contact> onRename;
  final ValueChanged<Contact> onDelete;

  const _ContactsSection({
    required this.loading,
    required this.contacts,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '联系人',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            if (contacts.isNotEmpty)
              Text('${contacts.length}', style: theme.textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 8),
        if (contacts.isEmpty)
          const _EmptyContacts()
        else
          for (var i = 0; i < contacts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ContactCard(
              contact: contacts[i],
              onOpen: onOpen,
              onRename: onRename,
              onDelete: onDelete,
            ),
          ],
      ],
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 18, color: scheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '还没有联系人。通过邀请建立连接后会出现在这里。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final ValueChanged<Contact> onOpen;
  final ValueChanged<Contact> onRename;
  final ValueChanged<Contact> onDelete;

  const _ContactCard({
    required this.contact,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.palette;
    final time = contact.lastActivity;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onOpen(contact),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              _ContactAvatar(name: contact.displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    contact.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleSmall?.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (contact.verified) ...[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: '身份已核实',
                                    child: Icon(
                                      Icons.verified_user,
                                      size: 14,
                                      color: palette.success,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (time != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatContactTime(time),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10.5,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: contact.lastMessage == null
                            ? scheme.outline
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '联系人操作',
                padding: const EdgeInsets.all(10),
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: scheme.outline,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename(contact);
                    case 'delete':
                      onDelete(contact);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('重命名'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _DeleteContactItem(),
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

class _ContactAvatar extends StatelessWidget {
  final String name;

  const _ContactAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _DeleteContactItem extends StatelessWidget {
  const _DeleteContactItem();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.delete_outline, size: 18, color: scheme.error),
        const SizedBox(width: 10),
        Text('删除', style: TextStyle(color: scheme.error)),
      ],
    );
  }
}

String _formatContactTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  if (day == today.subtract(const Duration(days: 1))) return '昨天';
  if (time.year == now.year) return '${time.month}月${time.day}日';
  return '${time.year}/${time.month}/${time.day}';
}

class _BrandMark extends StatelessWidget {
  final VoidCallback onLongPress;

  const _BrandMark({required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;

    return Tooltip(
      message: '长按可重置身份',
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary,
                    Color.lerp(scheme.primary, scheme.tertiary, 0.3)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                Icons.door_front_door_outlined,
                size: 42,
                color: scheme.onPrimary,
              ),
            ),
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.success.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: palette.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: -140,
          right: -100,
          child: _Glow(
            size: 340,
            color: scheme.primary.withValues(alpha: 0.13),
          ),
        ),
        Positioned(
          bottom: -160,
          left: -120,
          child: _Glow(
            size: 380,
            color: scheme.tertiary.withValues(alpha: 0.09),
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

class _ServerDialog extends StatefulWidget {
  final String initial;
  final String? envServer;

  const _ServerDialog({required this.initial, this.envServer});

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initial;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _controller.text;
    final error = Session.validateServerAddress(raw);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final session = context.read<Session>();
    setState(() {
      _saving = true;
      _error = null;
    });
    var ok = false;
    try {
      ok = await session.setServer(raw);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final envServer = widget.envServer?.trim();
    final hasEnv = envServer != null && envServer.isNotEmpty;

    return AlertDialog(
      title: const Text('服务器设置'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                style: monoStyle(context, fontSize: 13, letterSpacing: 0.2),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: Session.defaultServerAddress,
                  errorText: _error,
                  helperText: '用于创建新门；加入链接时以链接里的服务器为准。',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '格式 host:port；不写端口时按 wss 443 处理。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (hasEnv) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '当前由环境变量 KNOCK_SERVER 指定为 $envServer；'
                    '去掉环境变量后，这里保存的地址才会生效。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

class _RenameContactDialog extends StatefulWidget {
  final Contact contact;

  const _RenameContactDialog({required this.contact});

  @override
  State<_RenameContactDialog> createState() => _RenameContactDialogState();
}

class _RenameContactDialogState extends State<_RenameContactDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.contact.alias ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('重命名联系人'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 24,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                hintText: '例如：小周',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '指纹 ${groupFingerprint(widget.contact.fingerprint)}',
              style: monoStyle(
                context,
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
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

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('粘贴对方的邀请链接'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              style: monoStyle(context, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'knock://...',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: scheme.outline,
                ),
                prefixIcon: const Icon(Icons.link, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '需要包含公钥参数 k 的 v2 链接',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const Text('粘贴'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('连接'),
        ),
      ],
    );
  }
}
