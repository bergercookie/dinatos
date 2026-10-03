import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/responsive_body.dart';

/// Version, build commit, documentation link and copyright notice.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
                    title: const Text('Version'),
                    subtitle: Text(appVersion),
                  ),
                  ListTile(
                    leading: const Icon(Icons.commit),
                    title: const Text('Built from commit'),
                    subtitle: SelectableText(commitShort),
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
