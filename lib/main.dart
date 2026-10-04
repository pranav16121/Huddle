import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/auto_backup.dart';
import 'data/repository.dart';
import 'data/store.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  try {
    final repo = await SqliteRepository.open();
    final snapshot = await repo.load();
    final store = HuddleStore(repo, snapshot);
    final backups = await AutoBackups.open();
    backups.attach(store);
    // Early versions could load a sample season; clear it out (safely).
    if (store.hasDemoData) await store.removeDemoData();
    runApp(HuddleApp(store: store, backups: backups));
    // Today's backup, without holding up the first frame.
    backups.daily(store);
  } catch (e, st) {
    debugPrint('Huddle failed to start: $e\n$st');
    runApp(_StartupError(error: e));
  }
}

/// Shown only if the on-device database can't be opened at all.
class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.sports_basketball,
                  size: 56,
                  color: Brand.orange,
                ),
                const SizedBox(height: 20),
                Text(
                  'Huddle couldn\'t open its data',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your attendance is still safe on this phone. Try closing and '
                  'reopening the app. If it keeps happening, restarting the '
                  'phone usually helps.\n\nDetails: $error',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
