import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/responsive_body.dart';
import 'admin_providers.dart';
import 'admin_repository.dart';

/// Lists every account and lets an admin add one -- the way in when
/// self-registration is turned off (`DINATOS_ALLOW_REGISTRATION=false`).
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
            ],
          ),
        ),
      ),
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
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
