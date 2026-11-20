// Atomic, crash-safe save file: write a temp file, keep the previous good file
// as a backup, then rename. A torn or corrupted save falls back to the backup,
// and only if both are unreadable does the player start fresh.
import 'dart:convert';
import 'dart:io';

import 'save_data.dart';

class SaveStore {
  SaveStore(this.dir);

  final Directory dir;
  File get _main => File('${dir.path}/save.json');
  File get _backup => File('${dir.path}/save.bak.json');
  File get _temp => File('${dir.path}/save.tmp');

  SaveData load() {
    for (final f in [_main, _backup]) {
      try {
        if (f.existsSync()) return SaveData.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, Object?>);
      } on Object {
        // Unreadable: try the next one.
      }
    }
    return SaveData();
  }

  // ponytail: synchronous; the file is ~1 KB. Move to an isolate if it ever grows.
  void save(SaveData data) {
    dir.createSync(recursive: true);
    _temp.writeAsStringSync(jsonEncode(data.toJson()), flush: true);
    if (_main.existsSync()) _main.copySync(_backup.path);
    _temp.renameSync(_main.path); // atomic within one directory
  }
}
