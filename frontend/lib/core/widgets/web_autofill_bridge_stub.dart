import 'package:flutter/widgets.dart';

import 'web_autofill_field.dart';

/// Native targets (Android, Linux) have no DOM: the platform's own autofill
/// framework drives `AutofillGroup`/`autofillHints` directly. Nothing to do;
/// see web_autofill_bridge_web.dart for the browser version.
VoidCallback bindWebAutofill(List<WebAutofillField> fields) => () {};
