import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Keeps Flutter's semantics tree alive for as long as it's mounted, on web.
///
/// Why this exists: Flutter web paints text fields to a canvas, and only
/// creates a real DOM `<input>` for the one field that currently has focus
/// -- a zero-sized, off-screen one at that. A password manager (Bitwarden
/// et al.) sees no fillable field at all, or offers to fill one and then
/// reports "unable to auto-fill". With semantics enabled, Flutter instead
/// mounts a persistent, correctly-sized `<input>` per text field, which is
/// what password managers can find and fill. Scoped to the screens that need
/// it (login/register) so the rest of the app doesn't pay for the extra tree.
class WebAutofillSemantics extends StatefulWidget {
  const WebAutofillSemantics({super.key, required this.child});

  final Widget child;

  @override
  State<WebAutofillSemantics> createState() => _WebAutofillSemanticsState();
}

class _WebAutofillSemanticsState extends State<WebAutofillSemantics> {
  SemanticsHandle? _handle;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _handle = SemanticsBinding.instance.ensureSemantics();
  }

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
