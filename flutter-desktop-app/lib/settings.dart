/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

/// Which request groups are skipped (never stored / never shown).
class SkipSettings {
  const SkipSettings({
    this.images = true,
    this.scripts = true,
    this.fonts = true,
    this.media = true,
    this.downloads = false,
    this.hidePreflight = false,
  });

  final bool images;
  final bool scripts;
  final bool fonts;
  final bool media;
  final bool downloads;
  final bool hidePreflight;

  bool get anySkipped => images || scripts || fonts || media || downloads;

  SkipSettings copyWith({
    bool? images,
    bool? scripts,
    bool? fonts,
    bool? media,
    bool? downloads,
    bool? hidePreflight,
  }) =>
      SkipSettings(
        images: images ?? this.images,
        scripts: scripts ?? this.scripts,
        fonts: fonts ?? this.fonts,
        media: media ?? this.media,
        downloads: downloads ?? this.downloads,
        hidePreflight: hidePreflight ?? this.hidePreflight,
      );

  factory SkipSettings.fromJson(Map<String, dynamic> j) => SkipSettings(
        images: j['images'] != false,
        scripts: j['scripts'] != false,
        fonts: j['fonts'] != false,
        media: j['media'] != false,
        downloads: j['downloads'] == true,
        hidePreflight: j['hidePreflight'] == true,
      );

  Map<String, dynamic> toJson() => {
        'images': images,
        'scripts': scripts,
        'fonts': fonts,
        'media': media,
        'downloads': downloads,
        'hidePreflight': hidePreflight,
      };
}

class AppSettings {
  AppSettings({this.skip = const SkipSettings()});

  SkipSettings skip;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        skip: j['skip'] is Map
            ? SkipSettings.fromJson(Map<String, dynamic>.from(j['skip']))
            : const SkipSettings(),
      );

  Map<String, dynamic> toJson() => {'skip': skip.toJson()};
}

/// Loads/saves settings next to the database in %LOCALAPPDATA%.
class SettingsStore {
  SettingsStore(this.path);

  final String path;

  static String defaultPath() {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    return '$base\\NetworkLogViewer\\settings.json';
  }

  AppSettings load() {
    try {
      final file = File(path);
      if (!file.existsSync()) return AppSettings();
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // corrupt/missing -> defaults
    }
    return AppSettings();
  }

  void save(AppSettings settings) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(settings.toJson()));
    } catch (_) {
      // ignore persistence errors
    }
  }
}
