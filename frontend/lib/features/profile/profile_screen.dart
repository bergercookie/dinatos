import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/design_tokens.dart';
import '../../core/insecure_tls_provider.dart';
import '../../core/server_url_provider.dart';
import '../../core/widgets/error_banner.dart';
import '../../models/profile.dart';
import 'profile_providers.dart';
import 'profile_repository.dart';

/// Changing servers makes the current session meaningless on the new one --
/// logs out (revoking the session against the *old* server first) before
/// switching, rather than letting the switch happen first and leaning on
/// the next bootstrap's 401 to sort it out.
Future<void> _editServerUrl(BuildContext context, WidgetRef ref) async {
  final newUrl = await showDialog<String>(
    context: context,
    builder: (context) => _ServerUrlDialog(initialUrl: ref.read(serverUrlProvider)),
  );
  if (newUrl == null || newUrl.isEmpty || newUrl == ref.read(serverUrlProvider)) return;
  await ref.read(authNotifierProvider.notifier).logout();
  await ref.read(serverUrlStorageProvider).write(newUrl);
  ref.read(serverUrlProvider.notifier).state = newUrl;
}

/// A dedicated `State` so its `TextEditingController` is disposed by
/// Flutter's own widget lifecycle, not by us -- `showDialog`'s Future
/// completes as soon as `Navigator.pop` is called, well before the dialog's
/// exit *animation* has run a single frame, so a controller disposed right
/// after `await showDialog(...)` races a `TextField` that's still mounted
/// and still rebuilding as it animates out. `State.dispose()` only runs
/// once the framework has actually finished removing this widget.
class _ServerUrlDialog extends StatefulWidget {
  const _ServerUrlDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ServerUrlDialog> createState() => _ServerUrlDialogState();
}

class _ServerUrlDialogState extends State<_ServerUrlDialog> {
  late final _controller = TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server URL'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Server URL'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final profileAsync = ref.watch(profileProvider);
    final email = authState is AuthAuthenticated ? authState.user.email : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: AsyncValueView(
        value: profileAsync,
        onRetry: () => ref.invalidate(profileProvider),
        builder: (context, profile) =>
            _ProfileForm(email: email, profile: profile, serverUrl: ref.watch(serverUrlProvider)),
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.email, required this.profile, required this.serverUrl});

  final String? email;
  final Profile profile;
  final String serverUrl;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _heightController = TextEditingController(text: widget.profile.heightCm?.toString());
  late UnitSystem _unitSystem = widget.profile.unitSystem;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .update(
            Profile(heightCm: double.tryParse(_heightController.text), unitSystem: _unitSystem),
          );
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        const _SectionHeader('Account'),
        Card(
          child: Column(
            children: [
              if (widget.email != null)
                ListTile(
                  leading: const Icon(Icons.alternate_email_rounded),
                  title: const Text('Email'),
                  subtitle: Text(widget.email!),
                ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server'),
                subtitle: Text(widget.serverUrl),
                trailing: IconButton(
                  tooltip: 'Change server',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editServerUrl(context, ref),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.lock_open_outlined),
                title: const Text('Allow self-signed certificates'),
                subtitle: const Text('Skips TLS certificate verification for this server'),
                value: ref.watch(allowInsecureTlsProvider),
                onChanged: (value) async {
                  await ref.read(insecureTlsStorageProvider).write(value);
                  ref.read(allowInsecureTlsProvider.notifier).state = value;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionHeader('Data'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Import from Hevy'),
                subtitle: const Text('Upload your Hevy workout/measurement CSV exports'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go('/profile/import-hevy'),
              ),
              ListTile(
                leading: const Icon(Icons.api_outlined),
                title: const Text('API documentation'),
                subtitle: const Text('Browse and try out the REST API'),
                trailing: const Icon(Icons.chevron_right_rounded),
                // `go`, not `push`: verified in a real browser that `push`
                // renders this screen but leaves the address bar on
                // `#/profile`, so the /docs link couldn't be copied,
                // bookmarked or reloaded. `go` leaves nothing to pop, which
                // is why the docs screen carries its own explicit back button.
                onTap: () => context.go('/docs'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionHeader('Preferences'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                TextField(
                  controller: _heightController,
                  decoration: const InputDecoration(labelText: 'Height (cm)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<UnitSystem>(
                  initialValue: _unitSystem,
                  decoration: const InputDecoration(labelText: 'Unit system'),
                  items: UnitSystem.values
                      .map((unit) => DropdownMenuItem(value: unit, child: Text(unit.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _unitSystem = value);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
