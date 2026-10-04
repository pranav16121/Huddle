import 'package:flutter/material.dart';

import 'data/auto_backup.dart';
import 'data/store.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/scope.dart';
import 'ui/theme.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

class HuddleApp extends StatefulWidget {
  const HuddleApp({super.key, required this.store, this.backups});

  final HuddleStore store;
  final AutoBackups? backups;

  @override
  State<HuddleApp> createState() => _HuddleAppState();
}

class _HuddleAppState extends State<HuddleApp> with WidgetsBindingObserver {
  late ThemeMode _themeMode = widget.store.themeMode;
  late bool _onboarded = widget.store.onboarded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_onStoreChanged);
    widget.store.onPersistError = (_) {
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t save that change. Please try again.'),
          ),
        );
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  // Refresh today's backup whenever the coach leaves the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.backups?.daily(widget.store);
    }
  }

  // Only the theme and onboarding state affect the app shell; everything else
  // is handled by the screens that care.
  void _onStoreChanged() {
    final store = widget.store;
    if (store.themeMode != _themeMode || store.onboarded != _onboarded) {
      setState(() {
        _themeMode = store.themeMode;
        _onboarded = store.onboarded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackupScope(
      backups: widget.backups,
      child: StoreScope(
        store: widget.store,
        child: MaterialApp(
          title: 'Huddle',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messengerKey,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: _themeMode,
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            child: _onboarded
                ? const HomeShell(key: ValueKey('home'))
                : const OnboardingScreen(key: ValueKey('welcome')),
          ),
        ),
      ),
    );
  }
}
