import 'package:flutter/widgets.dart';

/// One text field a password manager should be able to find and fill: the
/// [label] it shows (what the web build's `<input>` is named by), its
/// [controller], and the standard HTML `autocomplete` token and `name` to
/// advertise for it (`username`, `current-password`, `new-password`, ...).
class WebAutofillField {
  const WebAutofillField({
    required this.label,
    required this.controller,
    required this.autocomplete,
    required this.name,
  });

  final String label;
  final TextEditingController controller;
  final String autocomplete;
  final String name;
}
