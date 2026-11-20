import 'package:flutter/material.dart';

import '../game/play_kit.dart';
import '../meta/progress.dart';
import 'brand.dart';
import 'tokens.dart';

/// Saved settings. Sound and music take effect once audio lands (Phase 7).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.s),
        child: Text(t.toUpperCase(), style: PourText.label.copyWith(color: PourColors.textMuted)),
      );

  Widget _toggle(String title, bool value, void Function(bool) set) => SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: (v) => setState(() => progress.updateSettings((_) => set(v))),
      );

  @override
  Widget build(BuildContext context) {
    final s = progress.settings;
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: PourText.heading)),
      body: ListView(
        children: [
          _header('Controls'),
          ...tiltSettingTiles(setState),
          _header('Sound & feel'),
          _toggle('Sound effects', s.sound, (v) => s.sound = v),
          _toggle('Music', s.music, (v) => s.music = v),
          _toggle('Vibration', s.haptics, (v) => s.haptics = v),
          _header('About'),
          ListTile(
            title: const Text('Licences'),
            subtitle: const Text('Fonts and open-source software'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Pour',
              applicationIcon: const Padding(padding: EdgeInsets.all(Space.s), child: LogoMark(size: 48)),
            ),
          ),
          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }
}
