import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/scoreboard.dart';
import 'roster_screen.dart' show parseNames;
import 'squads_screen.dart' show ColorPicker, WeekdayPicker;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _coach = TextEditingController();
  final _squad = TextEditingController();
  final _players = TextEditingController();
  final Set<int> _days = {};
  int _color = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _coach.text = context.readStore.coachName;
  }

  @override
  void dispose() {
    _pages.dispose();
    _coach.dispose();
    _squad.dispose();
    _players.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    setState(() => _page = page);
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() {
    final store = context.readStore;
    HapticFeedback.mediumImpact();
    store.setCoachName(_coach.text);
    final squad = store.addSquad(
      name: _squad.text.trim().isEmpty ? 'My Squad' : _squad.text.trim(),
      colorIndex: _color,
      weekdays: _days,
    );
    store.addPlayers(parseNames(_players.text), {squad.id});
    store.setOnboarded();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_page - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: PageView(
            controller: _pages,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _Welcome(onStart: () => _go(1)),
              _Step(
                step: 1,
                title: 'Your first squad',
                subtitle: 'A squad is a group you coach together.',
                onBack: () => _go(0),
                primaryLabel: 'Next',
                onPrimary: _squad.text.trim().isEmpty ? null : () => _go(2),
                children: [
                  TextField(
                    controller: _coach,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Your name (optional)',
                      hintText: 'Coach Sam',
                      prefixIcon: Icon(Icons.sports_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _squad,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Squad name',
                      hintText: 'e.g. U10 Saturday',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('TRAINING DAYS', style: context.text.labelSmall),
                  const SizedBox(height: 10),
                  WeekdayPicker(
                    selected: _days,
                    onChanged: (d) => setState(() {
                      _days.contains(d) ? _days.remove(d) : _days.add(d);
                    }),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'On these days the squad is ready to go the moment you '
                    'open the app.',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 22),
                  Text('COLOUR', style: context.text.labelSmall),
                  const SizedBox(height: 10),
                  ColorPicker(
                    selected: _color,
                    onChanged: (i) => setState(() => _color = i),
                  ),
                ],
              ),
              _Step(
                step: 2,
                title: 'Who\'s on the squad?',
                subtitle:
                    'Type or paste one name per line. You can always add '
                    'more later.',
                onBack: () => _go(1),
                primaryLabel: parseNames(_players.text).isEmpty
                    ? 'Skip for now'
                    : 'Add ${plural(parseNames(_players.text).length, 'player')}',
                onPrimary: _finish,
                children: [
                  TextField(
                    controller: _players,
                    minLines: 8,
                    maxLines: 14,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Maya Rodriguez\nLeo Kim\nAarav Mehta\n…',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          const Center(child: _BouncingBall()),
          const SizedBox(height: 28),
          Text(
            'HUDDLE',
            textAlign: TextAlign.center,
            style: context.text.displayLarge?.copyWith(
              letterSpacing: 6,
              fontSize: 64,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Roll call in seconds.\nBack to coaching.',
            textAlign: TextAlign.center,
            style: context.text.titleLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const Spacer(flex: 3),
          FilledButton(
            onPressed: onStart,
            child: const Text('Set up my squad'),
          ),
          const SizedBox(height: 14),
          Text(
            'Works offline. Your data never leaves this phone.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BouncingBall extends StatefulWidget {
  const _BouncingBall();

  @override
  State<_BouncingBall> createState() => _BouncingBallState();
}

class _BouncingBallState extends State<_BouncingBall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    const drop = 70.0;
    return SizedBox(
      width: 160,
      height: size + drop + 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Height follows a parabola; squash briefly on contact.
          final h = 1 - math.pow(2 * t - 1, 2).toDouble();
          final contact = (1 - h) > 0.92 ? ((1 - h) - 0.92) / 0.08 : 0.0;
          final squashY = 1 - 0.14 * contact;
          final squashX = 1 + 0.12 * contact;
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Shadow grows as the ball comes down.
              Positioned(
                bottom: 0,
                child: Container(
                  width: size * (0.5 + 0.45 * (1 - h)),
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: 0.06 + 0.12 * (1 - h),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                bottom: 5 + drop * h,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(squashX, squashY, 1),
                  child: Basketball(size: size, rotation: t * math.pi * 0.6),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.primaryLabel,
    required this.onPrimary,
    required this.children,
  });

  final int step;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              const Spacer(),
              for (var i = 1; i <= 2; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(left: 6),
                  width: i == step ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= step
                        ? Brand.orange
                        : context.colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(title, style: context.text.displaySmall),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: context.text.bodyLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        ),
      ],
    );
  }
}
