import 'dart:convert';

import '../media/media_kind.dart';

/// One row of a library's Recommended tab and whether it is shown.
class LibraryRowSetting {
  const LibraryRowSetting(this.id, {this.enabled = true});

  final String id;
  final bool enabled;

  LibraryRowSetting copyWith({bool? enabled}) => LibraryRowSetting(id, enabled: enabled ?? this.enabled);

  Map<String, Object> toJson() => {'id': id, 'on': enabled};
}

/// The rows a movie or TV library's Recommended tab can show, their defaults
/// and their saved form.
abstract final class LibraryRows {
  static const continueWatching = 'continue';
  static const released = 'released';
  static const newEpisodes = 'newepisodes';
  static const because = 'because';
  static const gems = 'gems';
  static const topRated = 'toprated';
  static const collections = 'collections';
  static const explore = 'explore';
  static const recentlyAdded = 'recent';

  /// Not a row: whether the library shows an Explore tab.
  static const exploreTab = 'exploretab';

  /// [exploreTab] is the Explore tab's default: on for a library's main
  /// movie or TV library and for anime, off for themed extras (a sleep or
  /// kids library) unless switched on.
  static List<LibraryRowSetting> defaults(MediaKind kind, {bool exploreTab = true}) =>
      _defaults(kind).map((row) => row.id == LibraryRows.exploreTab ? row.copyWith(enabled: exploreTab) : row).toList();

  static List<LibraryRowSetting> _defaults(MediaKind kind) => kind == MediaKind.movie
      ? const [
          LibraryRowSetting(continueWatching),
          LibraryRowSetting(released),
          LibraryRowSetting(because),
          LibraryRowSetting(gems),
          LibraryRowSetting(topRated),
          LibraryRowSetting(collections),
          LibraryRowSetting(explore),
          LibraryRowSetting(recentlyAdded, enabled: false),
          LibraryRowSetting(exploreTab),
        ]
      : const [
          LibraryRowSetting(continueWatching),
          LibraryRowSetting(newEpisodes),
          LibraryRowSetting(released),
          LibraryRowSetting(because),
          LibraryRowSetting(gems),
          LibraryRowSetting(topRated),
          LibraryRowSetting(explore),
          LibraryRowSetting(recentlyAdded, enabled: false),
          LibraryRowSetting(exploreTab),
        ];

  static String title(String id, MediaKind kind) => switch (id) {
    continueWatching => 'Continue Watching',
    released => kind == MediaKind.movie ? 'New Releases' : 'Latest Shows',
    newEpisodes => 'New Episodes',
    because => 'Because You Watched',
    gems => kind == MediaKind.movie ? 'Hidden Gems' : 'Unwatched Picks',
    topRated => 'Top Rated',
    collections => 'Finish the Collection',
    explore => 'Explore row',
    recentlyAdded => 'Recently Added',
    exploreTab => 'Explore tab',
    _ => id,
  };

  /// The saved order and switches. Rows the saved list does not know (added
  /// in a later version) follow in their default order; unknown ids are
  /// dropped.
  static List<LibraryRowSetting> parse(String? saved, MediaKind kind, {bool exploreTab = true}) {
    final defaults = LibraryRows.defaults(kind, exploreTab: exploreTab);
    if (saved == null || saved.isEmpty) return defaults;
    final List<Object?> decoded;
    try {
      final value = jsonDecode(saved);
      if (value is! List) return defaults;
      decoded = value;
    } on FormatException {
      return defaults;
    }
    final known = {for (final row in defaults) row.id: row};
    final rows = <LibraryRowSetting>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || known.remove(id) == null) continue;
      rows.add(LibraryRowSetting(id, enabled: entry['on'] != false));
    }
    return [...rows, ...known.values];
  }

  static String encode(List<LibraryRowSetting> rows) => jsonEncode([for (final row in rows) row.toJson()]);
}
