import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_library.dart';
import '../utils/content_utils.dart';

/// One icon a library can wear in the menus.
class LibraryIconChoice {
  const LibraryIconChoice(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

/// The icons a library can be given, the "no icon" choice, and the starting
/// icon for a library nobody has picked one for.
abstract final class LibraryIcons {
  /// Saved for a library that shows its name only.
  static const none = 'none';

  static const choices = <LibraryIconChoice>[
    LibraryIconChoice('movie', 'Film', Symbols.movie_rounded),
    LibraryIconChoice('tv', 'TV', Symbols.tv_rounded),
    LibraryIconChoice('live', 'Live TV', Symbols.live_tv_rounded),
    LibraryIconChoice('theater', 'Cinema', Symbols.theaters_rounded),
    LibraryIconChoice('anime', 'Anime', Symbols.auto_awesome_rounded),
    LibraryIconChoice('animation', 'Cartoon', Symbols.animation_rounded),
    LibraryIconChoice('sleep', 'Sleep', Symbols.bedtime_rounded),
    LibraryIconChoice('night', 'Night', Symbols.nights_stay_rounded),
    LibraryIconChoice('kids', 'Kids', Symbols.child_care_rounded),
    LibraryIconChoice('family', 'Family', Symbols.family_restroom_rounded),
    LibraryIconChoice('christmas', 'Christmas', Symbols.park_rounded),
    LibraryIconChoice('snow', 'Winter', Symbols.ac_unit_rounded),
    LibraryIconChoice('halloween', 'Halloween', Symbols.skull_rounded),
    LibraryIconChoice('documentary', 'Documentary', Symbols.public_rounded),
    LibraryIconChoice('nature', 'Nature', Symbols.forest_rounded),
    LibraryIconChoice('science', 'Science', Symbols.science_rounded),
    LibraryIconChoice('history', 'History', Symbols.history_edu_rounded),
    LibraryIconChoice('sport', 'Sport', Symbols.sports_soccer_rounded),
    LibraryIconChoice('fitness', 'Fitness', Symbols.fitness_center_rounded),
    LibraryIconChoice('comedy', 'Comedy', Symbols.sentiment_very_satisfied_rounded),
    LibraryIconChoice('drama', 'Drama', Symbols.theater_comedy_rounded),
    LibraryIconChoice('horror', 'Horror', Symbols.dark_mode_rounded),
    LibraryIconChoice('scifi', 'Sci-fi', Symbols.rocket_launch_rounded),
    LibraryIconChoice('food', 'Food', Symbols.restaurant_rounded),
    LibraryIconChoice('travel', 'Travel', Symbols.flight_rounded),
    LibraryIconChoice('music', 'Music', Symbols.music_note_rounded),
    LibraryIconChoice('concert', 'Concerts', Symbols.mic_external_on_rounded),
    LibraryIconChoice('photo', 'Photos', Symbols.photo_rounded),
    LibraryIconChoice('home', 'Home videos', Symbols.videocam_rounded),
    LibraryIconChoice('uk', 'UK', Symbols.flag_rounded),
    LibraryIconChoice('star', 'Favourites', Symbols.star_rounded),
    LibraryIconChoice('folder', 'Folder', Symbols.folder_rounded),
  ];

  static final Map<String, LibraryIconChoice> _byId = {for (final c in choices) c.id: c};

  static LibraryIconChoice? byId(String? id) => id == null ? null : _byId[id];

  /// The starting icon: by name for themed libraries ("Sleep", "Anime",
  /// "Kids", "Christmas"), otherwise by library type.
  static IconData defaultFor(MediaLibrary library) {
    final name = library.title.toLowerCase();
    for (final (word, id) in const [
      ('sleep', 'sleep'),
      ('anime', 'anime'),
      ('kid', 'kids'),
      ('christmas', 'christmas'),
      ('xmas', 'christmas'),
      ('documentar', 'documentary'),
      ('sport', 'sport'),
    ]) {
      if (name.contains(word)) return _byId[id]!.icon;
    }
    return ContentTypeHelper.getLibraryIcon(library.kind.id);
  }

  /// The icon to show for [library] given its saved choice: null means no
  /// icon (name only).
  static IconData? resolve(MediaLibrary library, String? saved) {
    if (saved == none) return null;
    return byId(saved)?.icon ?? defaultFor(library);
  }
}
