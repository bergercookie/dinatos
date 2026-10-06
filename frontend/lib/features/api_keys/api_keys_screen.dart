import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/api_key.dart';
import 'api_keys_providers.dart';
import 'api_keys_repository.dart';

/// Settings > API keys: the keys a person has made for tools (the MCP server,
/// scripts) to act as them. A key is shown once, when it is created.
class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(),
    );
    if (name == null || !context.mounted) return;
    try {
      final created = await ref.read(apiKeysRepositoryProvider).create(name);
      ref.invalidate(apiKeyListProvider);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _KeyCreatedDialog(created: created),
      );
    } on ApiException catch (error) {
      if (context.mounted) _snack(context, 'Could not create the key: ${error.message}');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ApiKeySummary key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${key.name}"?'),
        content: const Text(
          'Anything using this key stops working straight away. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete key'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiKeysRepositoryProvider).delete(key.id);
      ref.invalidate(apiKeyListProvider);
    } on ApiException catch (error) {
      if (context.mounted) _snack(context, 'Could not delete the key: ${error.message}');
    }
  }

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(apiKeyListProvider);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('API keys')),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Create API key',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Create key'),
      ),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: keys,
          onRetry: () => ref.invalidate(apiKeyListProvider),
          builder: (context, data) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl * 3,
              ),
              children: [
                Text(
                  'An API key lets a tool such as the MCP server use your account without your '
                  'password. A key is shown once, when you create it -- afterwards only its '
                  'name and last characters are kept, so copy it straight away. Delete a key '
                  'to cut that tool off.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (data.isEmpty)
                  const EmptyState(
                    icon: Icons.vpn_key_outlined,
                    title: 'No API keys yet',
                    message: 'Create one to connect the MCP server or a script.',
                  ),
                for (final key in data) ...[
                  AppListCard(
                    leading: const AppIconAvatar(icon: Icons.vpn_key_outlined),
                    title: key.name,
                    subtitle: Text(
                      'dnk_…${key.suffix} · created ${dateFormat.format(key.createdAt.toLocal())}'
                      ' · ${key.lastUsedAt == null ? 'never used' : 'last used ${dateFormat.format(key.lastUsedAt!.toLocal())}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete ${key.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, key),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create API key'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Claude on my laptop',
          helperText: 'So you can tell your keys apart later',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Shows the new key. It cannot be dismissed by a stray tap outside, and says
/// plainly that this is the only time the key is shown.
class _KeyCreatedDialog extends StatelessWidget {
  const _KeyCreatedDialog({required this.created});

  final CreatedApiKey created;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Key "${created.summary.name}" created'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Copy it now -- this is the only time it is shown. If you lose it, delete the '
              'key and make a new one.',
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: SelectableText(
                created.key,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: created.key));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Key copied to the clipboard')));
            }
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text("I've saved it")),
      ],
    );
  }
}
