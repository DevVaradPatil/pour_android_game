// Reusable game UI pieces. Sliders, switches, sheets and dialogs are plain
// Material widgets styled by theme.dart, so they don't get wrappers here.
import 'package:flutter/material.dart';

import '../services/audio.dart';
import 'tokens.dart';

/// Shrinks slightly while pressed: the toy-like "squish" every tappable thing shares.
class Squish extends StatefulWidget {
  const Squish({super.key, required this.child, this.onTap, this.scale = 0.94, this.sound = true});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// Plays the UI tap; off for controls with their own sound (valves, fans).
  final bool sound;

  @override
  State<Squish> createState() => _SquishState();
}

class _SquishState extends State<Squish> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _set(true),
    onTapUp: (_) => _set(false),
    onTapCancel: () => _set(false),
    onTap: widget.onTap == null
        ? null
        : () {
            if (widget.sound) audio.sfx(Sfx.tap, volume: 0.6);
            widget.onTap!();
          },
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Motion.fast,
      curve: Motion.standard,
      child: widget.child,
    ),
  );
}

enum PourButtonStyle { primary, secondary }

class PourButton extends StatelessWidget {
  const PourButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = PourButtonStyle.primary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PourButtonStyle style;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final primary = style == PourButtonStyle.primary;
    final bg = primary ? PourColors.accent : PourColors.surfaceHigh;
    final fg = primary ? PourColors.onAccent : PourColors.text;
    final lip = primary ? const Color(0xFFB8741A) : const Color(0xFF241C16);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Squish(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 120),
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.l),
              boxShadow: [BoxShadow(color: lip, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: Space.s)],
                Text(label, style: PourText.button.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 48,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Squish(
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: PourColors.surfaceHigh, shape: BoxShape.circle),
          child: Icon(icon, size: size * 0.5, color: PourColors.text),
        ),
      ),
    ),
  );
}

/// Pill showing a currency or count, e.g. coins or stars.
class CounterChip extends StatelessWidget {
  const CounterChip({super.key, required this.icon, required this.value, this.iconColor = PourColors.coin, this.label});
  final IconData icon;
  final int value;
  final Color iconColor;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${label ?? ''} $value'.trim(),
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.m, Space.xs),
      decoration: BoxDecoration(color: PourColors.surface, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: Space.xs),
          Text('$value', style: PourText.number),
        ],
      ),
    ),
  );
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 24});
  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$stars of 3 stars',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Icon(
            i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i < stars ? PourColors.accent : PourColors.outline,
          ),
      ],
    ),
  );
}

/// Horizontal fill meter (jar fill, spill, purity). Animates to [value] in 0..1.
class SandMeter extends StatelessWidget {
  const SandMeter({super.key, required this.value, this.color = PourColors.accent, this.height = 14, this.label});
  final double value;
  final Color color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${(value * 100).round()}%',
    child: Container(
      height: height,
      decoration: BoxDecoration(color: PourColors.surfaceHigh, borderRadius: BorderRadius.circular(height)),
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0, 1)),
        duration: Motion.medium,
        curve: Motion.standard,
        builder: (_, v, _) => FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
          ),
        ),
      ),
    ),
  );
}

enum LevelState { locked, open, current }

/// A level on the world map: number, stars earned, locked/current state.
class LevelNode extends StatelessWidget {
  const LevelNode({super.key, required this.number, this.stars = 0, this.state = LevelState.open, this.onTap});
  final int number;
  final int stars;
  final LevelState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = state == LevelState.locked;
    final current = state == LevelState.current;
    return Semantics(
      button: !locked,
      label: locked ? 'Level $number, locked' : 'Level $number, $stars stars',
      excludeSemantics: true,
      child: Squish(
        onTap: locked ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: locked ? PourColors.surface : (current ? PourColors.accent : PourColors.surfaceHigh),
                border: Border.all(color: current ? PourColors.text : PourColors.outline, width: current ? 3 : 2),
                boxShadow: const [BoxShadow(color: Color(0xFF120D0A), offset: Offset(0, 4))],
              ),
              child: locked
                  ? const Icon(Icons.lock_rounded, color: PourColors.outline)
                  : Text(
                      '$number',
                      style: PourText.title.copyWith(color: current ? PourColors.onAccent : PourColors.text),
                    ),
            ),
            const SizedBox(height: Space.xs),
            Opacity(
              opacity: locked ? 0 : 1,
              child: StarRow(stars: stars, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class PourCard extends StatelessWidget {
  const PourCard({super.key, required this.child, this.padding = const EdgeInsets.all(Space.l)});
  final Widget child;
  final EdgeInsets padding;

  @override
  // A Material (not a decorated Container) so ListTiles/ink inside still show splashes.
  Widget build(BuildContext context) => Material(
    color: PourColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.l),
      side: BorderSide(color: PourColors.outline.withValues(alpha: 0.5)),
    ),
    child: Padding(padding: padding, child: child),
  );
}
