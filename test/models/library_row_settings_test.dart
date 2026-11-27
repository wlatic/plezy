import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/library_row_settings.dart';

void main() {
  test('nothing saved gives the defaults with Recently Added off', () {
    final rows = LibraryRows.parse(null, MediaKind.show);
    expect(rows.first.id, LibraryRows.continueWatching);
    expect(rows.firstWhere((r) => r.id == LibraryRows.recentlyAdded).enabled, isFalse);
    expect(rows.any((r) => r.id == LibraryRows.newEpisodes), isTrue);
    expect(LibraryRows.parse(null, MediaKind.movie).any((r) => r.id == LibraryRows.newEpisodes), isFalse);
  });

  test('saved order and switches round-trip, unknown rows append in default order', () {
    final saved = LibraryRows.encode(const [
      LibraryRowSetting(LibraryRows.topRated),
      LibraryRowSetting(LibraryRows.continueWatching, enabled: false),
      LibraryRowSetting('somethingRemoved'),
    ]);
    final rows = LibraryRows.parse(saved, MediaKind.movie);
    expect(rows.take(2).map((r) => (r.id, r.enabled)), [
      (LibraryRows.topRated, true),
      (LibraryRows.continueWatching, false),
    ]);
    expect(rows.any((r) => r.id == 'somethingRemoved'), isFalse);
    expect(rows.length, LibraryRows.defaults(MediaKind.movie).length);
  });

  test('corrupt data falls back to the defaults', () {
    expect(LibraryRows.parse('not json', MediaKind.show).length, LibraryRows.defaults(MediaKind.show).length);
    expect(LibraryRows.parse('{"a":1}', MediaKind.show).first.id, LibraryRows.continueWatching);
  });

  test('Explore tab is a switch in the settings, on by default', () {
    for (final kind in [MediaKind.movie, MediaKind.show]) {
      expect(LibraryRows.defaults(kind).last.id, LibraryRows.exploreTab);
      expect(LibraryRows.defaults(kind).last.enabled, isTrue);
    }
  });

  test('a themed library defaults its Explore tab off, but a saved choice wins', () {
    bool exploreTab(List<LibraryRowSetting> rows) => rows.firstWhere((r) => r.id == LibraryRows.exploreTab).enabled;
    expect(exploreTab(LibraryRows.parse(null, MediaKind.show)), isTrue);
    expect(exploreTab(LibraryRows.parse(null, MediaKind.show, exploreTab: false)), isFalse);
    final saved = LibraryRows.encode([const LibraryRowSetting(LibraryRows.exploreTab)]);
    expect(exploreTab(LibraryRows.parse(saved, MediaKind.show, exploreTab: false)), isTrue);
    // Saved before the tab existed: the default for this library applies.
    final older = LibraryRows.encode([const LibraryRowSetting(LibraryRows.gems)]);
    expect(exploreTab(LibraryRows.parse(older, MediaKind.show, exploreTab: false)), isFalse);
  });
}
