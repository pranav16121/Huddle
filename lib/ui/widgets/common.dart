import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme.dart';

/// A player's face in the app: soft colour circle with initials, an optional
/// jersey patch and a status badge.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.player,
    this.size = 44,
    this.status,
    this.showJersey = true,
    this.heroTag,
  });

  final Player player;
  final double size;
  final AttendanceStatus? status;
  final bool showJersey;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = avatarColors(player.id, context.isDark);
    final s = status;
    Widget avatar = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.bg,
              shape: BoxShape.circle,
              border: player.archived
                  ? Border.all(color: context.colors.outlineVariant, width: 2)
                  : null,
            ),
            child: Text(
              player.initials,
              style: TextStyle(
                fontFamily: Brand.display,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.4,
                height: 1,
                color: c.fg,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (showJersey && player.jersey != null && size >= 40)
            Positioned(
              right: -size * 0.1,
              bottom: -size * 0.04,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.07,
                  vertical: size * 0.015,
                ),
                decoration: BoxDecoration(
                  color: context.isDark ? Brand.nightCardHigh : Brand.ink,
                  borderRadius: BorderRadius.circular(size * 0.12),
                  border: Border.all(
                    color: context.colors.surfaceContainerLowest,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  player.jersey!,
                  style: TextStyle(
                    fontFamily: Brand.display,
                    fontWeight: FontWeight.w800,
                    fontSize: math.max(10, size * 0.24),
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (s != null && s != AttendanceStatus.absent)
            Positioned(
              right: -size * 0.06,
              top: -size * 0.06,
              child: StatusBadge(status: s, size: math.max(18, size * 0.38)),
            ),
        ],
      ),
    );
    if (heroTag != null) {
      avatar = Hero(tag: heroTag!, child: avatar);
    }
    return avatar;
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.size = 20});

  final AttendanceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.statusColor(status),
        shape: BoxShape.circle,
        border: Border.all(
          color: context.colors.surfaceContainerLowest,
          width: math.max(1.5, size * 0.1),
        ),
      ),
      child: Icon(statusIcon(status), size: size * 0.62, color: Colors.white),
    );
  }
}

/// A small coloured pill showing a status.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.dense = false});

  final AttendanceStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: dense ? 13 : 15, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: dense ? 12 : 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scales down slightly while pressed — makes big tap targets feel physical.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 80 : 220),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// Animated attendance ring.
class RateRing extends StatelessWidget {
  const RateRing({
    super.key,
    required this.rate,
    this.size = 120,
    this.stroke = 12,
    this.child,
    this.color,
  });

  final double? rate;
  final double size;
  final double stroke;
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? rateColor(rate, context.isDark);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: rate ?? 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: value,
            stroke: stroke,
            color: color,
            track: context.colors.surfaceContainerHigh,
          ),
          child: Center(
            child:
                child ??
                Text(
                  formatRate(rate),
                  style: context.text.headlineLarge?.copyWith(
                    fontSize: size * 0.28,
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// A sports-style "form guide": recent sessions as dots, oldest on the left.
class FormGuide extends StatelessWidget {
  const FormGuide({
    super.key,
    required this.newestFirst,
    this.count = 5,
    this.dot = 9,
  });

  final List<AttendanceStatus> newestFirst;
  final int count;
  final double dot;

  @override
  Widget build(BuildContext context) {
    final items = newestFirst.take(count).toList().reversed.toList();
    final empty = context.colors.surfaceContainerHigh;
    return Semantics(
      label: 'Recent: ${items.map((s) => s.label).join(', ')}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: dot,
              height: dot,
              margin: EdgeInsets.only(left: i == 0 ? 0 : dot * 0.4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < count - items.length
                    ? empty
                    : context.statusColor(items[i - (count - items.length)]),
              ),
            ),
        ],
      ),
    );
  }
}

class SquadDot extends StatelessWidget {
  const SquadDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class SquadTag extends StatelessWidget {
  const SquadTag({super.key, required this.squad});

  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final color = context.squadColor(squad);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquadDot(color: color, size: 7),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              squad.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.isDark
                    ? Color.lerp(color, Colors.white, 0.35)
                    : Color.lerp(color, Colors.black, 0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 24, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.text.labelSmall?.copyWith(fontSize: 13),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Big page title used at the top of each tab.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.text.labelMedium?.copyWith(fontSize: 14),
                  ),
                Text(title, style: context.text.displaySmall),
              ],
            ),
          ),
          ...?actions,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon,
  });

  final String title;
  final String message;
  final Widget? action;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?icon,
          if (icon != null) const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

/// A rounded card with an optional tap handler.
class HCard extends StatelessWidget {
  const HCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A compact number + label tile for stats rows.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.icon,
  });

  final String value;
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return HCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: context.text.displaySmall?.copyWith(
                      fontSize: 34,
                      color: color,
                    ),
                  ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(icon, size: 22, color: color),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelMedium,
          ),
        ],
      ),
    );
  }
}

void showSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: Duration(seconds: actionLabel != null ? 5 : 3),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: context.text.bodyLarge),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: context.colors.error,
                  minimumSize: const Size(64, 46),
                )
              : FilledButton.styleFrom(minimumSize: const Size(64, 46)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}
