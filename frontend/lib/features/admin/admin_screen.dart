import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/design_tokens.dart';
import '../../core/file_io.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/responsive_body.dart';
import '../activities/activities_providers.dart';
import '../exercises/exercises_providers.dart';
import '../measurements/measurements_providers.dart';
import '../profile/profile_providers.dart';
import '../routines/routines_providers.dart';
import 'admin_providers.dart';
import 'admin_repository.dart';

/// Lists every account and lets an admin add one -- the way in when
/// self-registration is turned off (`DINATOS_ALLOW_REGISTRATION=false`) --
/// and download or restore a full backup of the server.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/profile'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (context) => const _CreateUserDialog(),
          );
          if (created == true) ref.invalidate(adminUsersProvider);
        },
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add user'),
      ),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: usersAsync,
          onRetry: () => ref.invalidate(adminUsersProvider),
          builder: (context, users) => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl * 2,
            ),
            children: [
              Card(
                child: Column(
                  children: [
                    for (final user in users)
                      ListTile(
                        leading: Icon(
                          user.isAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                        ),
                        title: Text(user.email),
                        subtitle: Text(user.isAdmin ? 'Admin' : 'Member'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _BackupCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-server backup and restore. The backup file holds every account's
/// password hash and stored API keys, so the download says so; the restore
/// replaces *everything* on the server, so it takes a typed confirmation.
class _BackupCard extends ConsumerStatefulWidget {
  const _BackupCard();

  @override
  ConsumerState<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<_BackupCard> {
  bool _busy = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(adminRepositoryProvider).downloadBackup();
      final saved = await ref.read(fileSaverProvider)(file);
      if (saved) {
        _message('Backup saved as ${file.name}. Keep it private: it contains password hashes.');
      }
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final file = await ref.read(jsonFilePickerProvider)();
    if (file == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RestoreConfirmDialog(fileName: file.name),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(adminRepositoryProvider).restoreBackup(file);
      final users = result.rows['users'] ?? 0;
      if (!result.sessionKept) {
        // The server ended this session too (the backup has no matching
        // account): the next request would be a 401 anyway.
        await ref.read(authNotifierProvider.notifier).logout();
        return;
      }
      ref.invalidate(adminUsersProvider);
      ref.invalidate(profileProvider);
      ref.invalidate(routineListProvider);
      ref.invalidate(activityListProvider);
      ref.invalidate(measurementListProvider);
      ref.invalidate(exerciseListProvider);
      ref.invalidate(exercisePagingProvider);
      _message('Restored the backup ($users accounts). Everyone else was logged out.');
    } on ApiException catch (error) {
      _message('Restore failed, nothing was changed: ${error.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
          child: Text(
            'BACKUP',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download full backup'),
                subtitle: const Text(
                  'Every account, exercise, routine, activity and measurement as one file. '
                  'Contains password hashes and API keys -- keep it private.',
                ),
                enabled: !_busy,
                onTap: _download,
              ),
              ListTile(
                leading: Icon(
                  Icons.restore_outlined,
                  color: _busy ? null : Theme.of(context).colorScheme.error,
                ),
                title: const Text('Restore from backup'),
                subtitle: const Text('Replaces everything on this server with a backup file'),
                enabled: !_busy,
                onTap: _restore,
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pops true only after the admin has typed `RESTORE`. Dedicated `State`
/// for its controller, same reasoning as [_CreateUserDialog].
class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({required this.fileName});

  final String fileName;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  static const _word = 'RESTORE';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
      title: const Text('Replace everything on this server?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restoring "${widget.fileName}" deletes ALL current data on this server -- every '
              'account, routine, activity and measurement -- and replaces it with the backup. '
              'This cannot be undone. Everyone is logged out; you stay logged in only if your '
              'account is in the backup.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Type $_word to confirm'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _controller.text.trim() == _word ? () => Navigator.pop(context, true) : null,
          child: const Text('Replace everything'),
        ),
      ],
    );
  }
}

/// A dedicated `State` for the same reason as profile_screen.dart's
/// `_ServerUrlDialog`: its controllers must outlive the dialog's exit
/// animation, which only the widget lifecycle knows about.
class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isAdmin = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .createUser(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            isAdmin: _isAdmin,
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Email is required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters',
                ),
                obscureText: true,
                validator: (value) => (value == null || value.length < 8)
                    ? 'Password must be at least 8 characters'
                    : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Administrator'),
                value: _isAdmin,
                onChanged: (value) => setState(() => _isAdmin = value ?? false),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                ErrorBanner(message: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Create')),
      ],
    );
  }
}
