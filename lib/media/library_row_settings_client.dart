import '../models/library_row_settings.dart';
import 'media_kind.dart';

/// A server that stores per-library Recommended-tab row settings for the
/// signed-in user, so every device shows the same rows.
abstract interface class LibraryRowSettingsClient {
  bool supportsLibraryRowSettings(MediaKind? kind);
  Future<List<LibraryRowSetting>> fetchLibraryRowSettings(String libraryId, MediaKind kind);
  Future<void> saveLibraryRowSettings(String libraryId, List<LibraryRowSetting> rows);
}
