import '../models/library_explore_focus.dart';
import '../models/library_row_settings.dart';
import 'media_kind.dart';

/// A server that stores per-library Recommended-tab row settings for the
/// signed-in user, so every device shows the same rows.
abstract interface class LibraryRowSettingsClient {
  bool supportsLibraryRowSettings(MediaKind? kind);
  Future<List<LibraryRowSetting>> fetchLibraryRowSettings(String libraryId, MediaKind kind);
  Future<void> saveLibraryRowSettings(String libraryId, List<LibraryRowSetting> rows);

  /// What [libraryId]'s Explore tab explores, or null for its general rows.
  Future<LibraryExploreFocus?> fetchLibraryExploreFocus(String libraryId);

  /// Save [focus] (null clears it). A focus also switches the Explore tab on.
  Future<void> saveLibraryExploreFocus(String libraryId, MediaKind kind, LibraryExploreFocus? focus);
}
