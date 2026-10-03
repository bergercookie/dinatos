import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'web_autofill_bridge.dart';

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
///
/// [fields] additionally makes those inputs fillable by an extension: see
/// [bindWebAutofill] for the attributes and the synthetic-event handling.
class WebAutofillSemantics extends StatefulWidget {
  const WebAutofillSemantics({super.key, required this.fields, required this.child});

  final List<WebAutofillField> fields;
  final Widget child;

  @override
  State<WebAutofillSemantics> createState() => _WebAutofillSemanticsState();
}

class _WebAutofillSemanticsState extends State<WebAutofillSemantics> {
  SemanticsHandle? _handle;
  VoidCallback? _unbind;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _handle = SemanticsBinding.instance.ensureSemantics();
      _unbind = bindWebAutofill(widget.fields);
    }
  }

  @override
  void dispose() {
    _unbind?.call();
    _handle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
