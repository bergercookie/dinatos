import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

import 'web_autofill_field.dart';

/// Makes the real `<input>` elements Flutter web mounts for [fields] (see
/// `WebAutofillSemantics`) work with browser extensions such as Bitwarden,
/// and returns a function that undoes it.
///
/// Two separate problems, both invisible to `flutter test`:
///
/// 1. Flutter builds those inputs itself and, from `autofillHints`, only
///    sets a (sometimes wrong) `autocomplete`, and never a `name`/`id`, so
///    an extension's heuristics can't tell a login form from any other.
///    A `MutationObserver` re-applies the right attributes whenever Flutter
///    (re)creates one.
/// 2. An extension fills a field by setting `input.value` and dispatching
///    synthetic `input`/`change` events, with no key events. Flutter's engine
///    does not turn that into a text-editing update for the framework, and
///    mirrors its own (empty) controller state back over the DOM value on
///    the next rebuild -- the extension "fills" the fields, they flash, and
///    stay empty. So untrusted (`isTrusted == false`) `input`/`change` events
///    are copied into the matching controller directly. Real typing is
///    trusted and left to Flutter alone.
///
/// Fields are matched by their `aria-label`, i.e. the label the field shows.
VoidCallback bindWebAutofill(List<WebAutofillField> fields) {
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final byLabel = {for (final field in fields) field.label: field};

  WebAutofillField? fieldFor(JSObject? element) {
    if (element == null || element.getProperty<JSAny?>('tagName'.toJS)?.dartify() != 'INPUT') {
      return null;
    }
    final label = element.callMethod<JSAny?>('getAttribute'.toJS, 'aria-label'.toJS)?.dartify();
    return label is String ? byLabel[label] : null;
  }

  void decorate(JSObject element) {
    final field = fieldFor(element);
    if (field == null) return;
    for (final (attribute, value) in [
      ('autocomplete', field.autocomplete),
      ('name', field.name),
      ('id', field.name),
    ]) {
      final current = element.callMethod<JSAny?>('getAttribute'.toJS, attribute.toJS)?.dartify();
      // Only when different: writing an attribute re-triggers the observer.
      if (current != value) {
        element.callMethod<JSAny?>('setAttribute'.toJS, attribute.toJS, value.toJS);
      }
    }
  }

  void decorateAll() {
    final inputs = document.callMethod<JSObject>('querySelectorAll'.toJS, 'input'.toJS);
    final length = (inputs.getProperty<JSNumber>('length'.toJS)).toDartInt;
    for (var i = 0; i < length; i++) {
      decorate(inputs.callMethod<JSObject>('item'.toJS, i.toJS));
    }
  }

  final onFill = ((JSObject event) {
    if (event.getProperty<JSBoolean?>('isTrusted'.toJS)?.toDart ?? true) return;
    final target = event.getProperty<JSObject?>('target'.toJS);
    final field = fieldFor(target);
    if (target == null || field == null) return;
    final value = target.getProperty<JSString?>('value'.toJS)?.toDart ?? '';
    if (field.controller.text == value) return;
    field.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }).toJS;

  // Capture phase, so this runs before Flutter's own handlers on the element.
  final capture = {'capture': true}.jsify();
  document
    ..callMethod<JSAny?>('addEventListener'.toJS, 'input'.toJS, onFill, capture)
    ..callMethod<JSAny?>('addEventListener'.toJS, 'change'.toJS, onFill, capture);

  final observer = globalContext
      .getProperty<JSFunction>('MutationObserver'.toJS)
      .callAsConstructor<JSObject>(((JSAny? _, JSAny? _) => decorateAll()).toJS);
  observer.callMethod<JSAny?>(
    'observe'.toJS,
    document.getProperty<JSObject>('body'.toJS),
    {'childList': true, 'subtree': true}.jsify(),
  );
  decorateAll();

  return () {
    observer.callMethod<JSAny?>('disconnect'.toJS);
    document
      ..callMethod<JSAny?>('removeEventListener'.toJS, 'input'.toJS, onFill, capture)
      ..callMethod<JSAny?>('removeEventListener'.toJS, 'change'.toJS, onFill, capture);
  };
}
