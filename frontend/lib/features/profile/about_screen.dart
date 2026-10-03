import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/external_link.dart';
import '../../core/update_check.dart';
import '../../core/widgets/responsive_body.dart';

/// UI (this app's) version, build commit, GitHub project and documentation
/// links, and copyright notice.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  bool _checking = false;
  UpdateCheckResult? _result;

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await ref.read(updateCheckProvider)();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  Widget _updateTile() {
    final result = _result;
    final (String subtitle, LatestRelease? release) = switch (result) {
      null => ('Look up the latest release on GitHub', null),
      UpToDate() => ('You are on the latest version', null),
      UpdateAvailable(:final release) => ('Version ${release.tag} is available', release),
      UnknownCurrentVersion(:final release) => (
        'Latest release is ${release.tag} (this is a development build)',
        release,
      ),
      NoReleasesYet() => ('No releases have been published yet', null),
      UpdateCheckFailed() => ("Couldn't check for updates -- are you offline?", null),
    };
    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: const Text('Check for updates'),
      subtitle: Text(subtitle),
      trailing: _checking
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : release != null
          ? const Icon(Icons.open_in_new_rounded)
          : const Icon(Icons.refresh),
      onTap: _checking
          ? null
          : release != null
          ? () => openExternalLink(context, ref, release.url)
          : _checkForUpdates,
    );
  }

  @override
  Widget build(BuildContext context) {
    final commitShort = appCommit.length > 7 ? appCommit.substring(0, 7) : appCommit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: BackButton(onPressed: () => context.go('/profile')),
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('UI version'),
                    subtitle: Text(appVersion),
                  ),
                  _updateTile(),
                  ListTile(
                    leading: const Icon(Icons.commit),
                    title: const Text('Built from commit'),
                    subtitle: SelectableText(commitShort),
                  ),
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('GitHub project'),
                    subtitle: const Text(githubUrl),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => openExternalLink(context, ref, githubUrl),
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('Documentation'),
                    subtitle: const Text(docsUrl),
                    trailing: const Icon(Icons.copy_rounded),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(const ClipboardData(text: docsUrl));
                      messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
                    },
                  ),
                  const ListTile(leading: Icon(Icons.copyright), title: Text(copyrightNotice)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
