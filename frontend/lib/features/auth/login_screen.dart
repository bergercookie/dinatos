import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_config.dart';
import '../../core/api_exception.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/design_tokens.dart';
import '../../core/insecure_tls_provider.dart';
import '../../core/server_url_provider.dart';
import '../../core/widgets/brand_header.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/web_autofill_semantics.dart';
import 'auth_config_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _serverUrlController = TextEditingController(text: ref.read(serverUrlProvider));
  late bool _allowInsecureTls = ref.read(allowInsecureTlsProvider);
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Persists and applies a changed server field (and/or TLS toggle)
  /// before logging in, so "Log in" always talks to whatever this screen
  /// currently says -- not whatever the app started up pointed at. Each
  /// setting is a no-op (no write, no rebuild of the API client) if it
  /// wasn't actually touched, and they're independent: toggling TLS alone,
  /// without editing the URL, still has to take effect.
  Future<void> _commitSettingsIfChanged() async {
    final url = _serverUrlController.text.trim();
    if (url.isNotEmpty && url != ref.read(serverUrlProvider)) {
      await ref.read(serverUrlStorageProvider).write(url);
      ref.read(serverUrlProvider.notifier).state = url;
    }
    if (_allowInsecureTls != ref.read(allowInsecureTlsProvider)) {
      await ref.read(insecureTlsStorageProvider).write(_allowInsecureTls);
      ref.read(allowInsecureTlsProvider.notifier).state = _allowInsecureTls;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _commitSettingsIfChanged();
      // Re-read *after* committing: a changed server URL rebuilds
      // [authNotifierProvider] (it depends on [dioProvider], which depends
      // on the server URL), so the notifier instance captured before that
      // commit would otherwise be a stale one talking to the old server.
      await ref
          .read(authNotifierProvider.notifier)
          .login(_emailController.text.trim(), _passwordController.text);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // A scroll view, not just Center+Column, now that the TLS checkbox's
      // extra row can push this past a short viewport's height (a small
      // window, a phone in landscape, or a keyboard eating vertical space)
      // -- overflowing silently past the edge is worse than a scrollbar.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: WebAutofillSemantics(
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandHeader(),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Log in to your workout tracker',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextFormField(
                        controller: _serverUrlController,
                        enabled: !ApiConfig.isFixedToServingOrigin,
                        decoration: const InputDecoration(labelText: 'Server URL'),
                        keyboardType: TextInputType.url,
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Server URL is required'
                            : null,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Allow self-signed certificates'),
                        subtitle: const Text('Skips TLS certificate verification for this server'),
                        value: _allowInsecureTls,
                        onChanged: (value) => setState(() => _allowInsecureTls = value ?? false),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        validator: (value) =>
                            (value == null || value.isEmpty) ? 'Email is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) =>
                            (value == null || value.isEmpty) ? 'Password is required' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Log in'),
                      ),
                      // Hidden until the server says registration is open (and
                      // while it's still being asked): an admin creates
                      // accounts under Profile > Administration instead.
                      if (ref.watch(registrationEnabledProvider).valueOrNull ?? false)
                        TextButton(
                          // Commits a changed server field before leaving, the
                          // same as "Log in" -- register() runs against whatever
                          // this screen's field says, not whatever the app
                          // started up pointed at, so it has to be applied
                          // whichever way the person leaves this screen.
                          onPressed: () async {
                            await _commitSettingsIfChanged();
                            if (context.mounted) context.go('/register');
                          },
                          child: const Text("Don't have an account? Register"),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
