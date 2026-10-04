import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class BarDatum {
  const BarDatum({required this.value, required this.label, required this.caption});

  /// 0..1, or null when there's nothing to show for this bar.
  final double? value;

  /// Short axis label ("Sep").
  final String label;

  /// Shown above the chart when the bar is selected.
  final String caption;
}

/// Attendance-rate bars. Tap (or drag across) a bar to see its details.
class RateBars extends StatefulWidget {
  const RateBars({
    super.key,
    required this.data,
    this.height = 150,
    this.showAllLabels = false,
    this.average,
  });

  final List<BarDatum> data;
  final double height;
  final bool showAllLabels;
  final double? average;

  @override
  State<RateBars> createState() => _RateBarsState();
}

class _RateBarsState extends State<RateBars> {
  int? _selected;

  @override
  void didUpdateWidget(RateBars old) {
    super.didUpdateWidget(old);
    if (_selected != null && _selected! >= widget.data.length) _selected = null;
  }

  void _select(Offset local, double width) {
    if (widget.data.isEmpty) return;
    final i = (local.dx / width * widget.data.length).floor().clamp(
      0,
      widget.data.length - 1,
    );
    if (i != _selected) {
      HapticFeedback.selectionClick();
      setState(() => _selected = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final selected = _selected ?? (data.isEmpty ? null : data.length - 1);
    final dark = context.isDark;
    final faint = context.colors.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: selected == null
              ? null
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    data[selected].caption,
                    key: ValueKey(selected),
                    style: context.text.titleSmall,
                  ),
                ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _select(d.localPosition, width),
              onHorizontalDragUpdate: (d) => _select(d.localPosition, width),
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  children: [
                    // Gridlines at 50% and 100%.
                    for (final f in [0.5, 1.0])
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: widget.height * f - 1,
                        child: Container(height: 1, color: faint),
                      ),
                    if (widget.average != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: widget.height * widget.average!.clamp(0, 1),
                        child: CustomPaint(
                          size: Size(width, 1.5),
                          painter: _DashPainter(
                            context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < data.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: data.length > 20 ? 1.5 : 3.5,
                              ),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: data[i].value ?? 0),
                                duration: Duration(
                                  milliseconds: 500 + (i * 18).clamp(0, 400),
                                ),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => Container(
                                  height: data[i].value == null
                                      ? 3
                                      : (widget.height * v).clamp(
                                          3,
                                          widget.height,
                                        ),
                                  decoration: BoxDecoration(
                                    color: data[i].value == null
                                        ? faint
                                        : rateColor(data[i].value, dark)
                                              .withValues(
                                                alpha: i == selected ? 1 : 0.5,
                                              ),
                                    borderRadius: BorderRadius.circular(
                                      data.length > 20 ? 3 : 6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        if (widget.showAllLabels)
          Row(
            children: [
              for (var i = 0; i < data.length; i++)
                Expanded(
                  child: Text(
                    data[i].label,
                    textAlign: TextAlign.center,
                    style: context.text.labelMedium?.copyWith(
                      fontSize: 12,
                      color: i == selected ? context.colors.onSurface : null,
                    ),
                  ),
                ),
            ],
          )
        else if (data.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(data.first.label, style: context.text.labelMedium),
              Text(data.last.label, style: context.text.labelMedium),
            ],
          ),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
