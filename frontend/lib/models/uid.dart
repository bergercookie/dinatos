int _lastUid = 0;

/// A process-unique id for an item being edited on screen -- never sent to
/// the server. Widgets key a row on it so that removing or reordering one
/// doesn't leave a neighbour's text field showing the removed row's text
/// (a `TextFormField`'s `initialValue` is only read once, when its state is
/// created). `0` means "none assigned", which is what a `const` item has.
int nextUid() => ++_lastUid;

/// The key a list row for an edited item should have: its [uid] if it was
/// given one, else its server [id], else (a `const` item nobody numbered) its
/// position -- which is no worse than not keying at all.
String itemKeyOf({required int uid, int? id, required int index}) =>
    uid != 0 ? 'u$uid' : (id != null ? 'i$id' : 'p$index');
