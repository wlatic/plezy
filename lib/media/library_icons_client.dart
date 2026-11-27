/// A server that stores the signed-in user's chosen library icons, so every
/// device shows the same ones.
abstract interface class LibraryIconsClient {
  bool get supportsLibraryIcons;

  /// Saved icon ids by library id.
  Future<Map<String, String>> fetchLibraryIcons();

  /// Save [iconId] for [libraryId]; null goes back to the starting icon.
  Future<void> saveLibraryIcon(String libraryId, String? iconId);
}
