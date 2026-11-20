import 'package:flutter/material.dart';

import '../game/palette.dart';
import 'brand.dart';
import 'components.dart';
import 'tokens.dart';

/// Dev screen showing every design-system piece. Also the golden-test source.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.scrollable = true});

  /// Golden tests render the whole page at once.
  final bool scrollable;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  double _slider = 0.6;
  bool _toggle = true;

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: PourText.label.copyWith(color: PourColors.textMuted)),
            const SizedBox(height: Space.m),
            child,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          'Brand',
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [Wordmark(height: 48), Spacer(), LogoMark(size: 56), SizedBox(width: Space.s), LogoMark(size: 32)],
          ),
        ),
        _section(
          'Sand colors + glyphs',
          Wrap(
            spacing: Space.l,
            runSpacing: Space.m,
            children: [
              for (final c in SandColor.values)
                Column(children: [SandGlyph(c, size: 40), Text(c.name, style: PourText.caption)]),
            ],
          ),
        ),
        _section(
          'Type',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pour', style: PourText.display),
              Text('Level complete', style: PourText.title),
              Text('Desert Glass · World 1', style: PourText.heading),
              Text('Tilt your phone to pour colored sand into every jar.', style: PourText.body),
              Text('PURITY 96%', style: PourText.label),
              Text('Fill line reached', style: PourText.caption.copyWith(color: PourColors.textMuted)),
            ],
          ),
        ),
        _section(
          'Buttons',
          Wrap(
            spacing: Space.m,
            runSpacing: Space.l,
            children: [
              PourButton(label: 'Play', icon: Icons.play_arrow_rounded, onPressed: () {}),
              PourButton(label: 'Retry', style: PourButtonStyle.secondary, onPressed: () {}),
              const PourButton(label: 'Locked', onPressed: null),
              RoundIconButton(icon: Icons.refresh_rounded, tooltip: 'Retry', onPressed: () {}),
              RoundIconButton(icon: Icons.center_focus_strong_rounded, tooltip: 'Recenter', onPressed: () {}),
              RoundIconButton(icon: Icons.pause_rounded, tooltip: 'Pause', onPressed: () {}),
            ],
          ),
        ),
        _section(
          'Counters + stars',
          const Wrap(
            spacing: Space.m,
            runSpacing: Space.m,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CounterChip(icon: Icons.monetization_on_rounded, value: 1250, label: 'coins'),
              CounterChip(icon: Icons.star_rounded, value: 42, iconColor: PourColors.accent, label: 'stars'),
              StarRow(stars: 0),
              StarRow(stars: 1),
              StarRow(stars: 2),
              StarRow(stars: 3),
            ],
          ),
        ),
        _section(
          'Meters',
          Column(
            children: [
              const SandMeter(value: 0.25, color: PourColors.danger, label: 'Spill'),
              const SizedBox(height: Space.m),
              SandMeter(value: 0.7, color: Color(0xFF000000 | SandColor.blue.rgb), label: 'Fill'),
              const SizedBox(height: Space.m),
              const SandMeter(value: 1, label: 'Purity'),
            ],
          ),
        ),
        _section(
          'Level nodes',
          const Wrap(
            spacing: Space.l,
            children: [
              LevelNode(number: 1, stars: 3),
              LevelNode(number: 2, stars: 1),
              LevelNode(number: 3, state: LevelState.current),
              LevelNode(number: 4, state: LevelState.locked),
            ],
          ),
        ),
        _section(
          'Card + controls',
          PourCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: PourText.heading),
                Slider(value: _slider, onChanged: (v) => setState(() => _slider = v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Haptics', style: PourText.body),
                  value: _toggle,
                  onChanged: (v) => setState(() => _toggle = v),
                ),
                PourButton(
                  label: 'Open sheet',
                  style: PourButtonStyle.secondary,
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xxl),
                      child: Text('Bottom sheet', style: PourText.title),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: widget.scrollable ? AppBar(title: Text('Design system', style: PourText.heading)) : null,
      body: SafeArea(
        child: widget.scrollable
            ? SingleChildScrollView(padding: const EdgeInsets.all(Space.l), child: content)
            : Padding(padding: const EdgeInsets.all(Space.l), child: content),
      ),
    );
  }
}
