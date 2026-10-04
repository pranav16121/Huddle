import 'package:flutter/widgets.dart';

import '../data/auto_backup.dart';
import '../data/store.dart';

/// Makes the [HuddleStore] available to the widget tree. Widgets that read it
/// through [StoreContext.store] rebuild whenever the data changes.
class StoreScope extends InheritedNotifier<HuddleStore> {
  const StoreScope({
    super.key,
    required HuddleStore store,
    required super.child,
  }) : super(notifier: store);

  static HuddleStore _find(BuildContext context, {required bool listen}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<StoreScope>()
        : context.getInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'No StoreScope above this widget.');
    return scope!.notifier!;
  }
}

extension StoreContext on BuildContext {
  /// The store, rebuilding this widget when it changes. Use in `build`.
  HuddleStore get store => StoreScope._find(this, listen: true);

  /// The store without subscribing. Use in callbacks.
  HuddleStore get readStore => StoreScope._find(this, listen: false);
}

/// Gives screens access to the automatic backups (null in tests).
class BackupScope extends InheritedWidget {
  const BackupScope({super.key, required this.backups, required super.child});

  final AutoBackups? backups;

  static AutoBackups? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BackupScope>()?.backups;

  @override
  bool updateShouldNotify(BackupScope old) => old.backups != backups;
}
