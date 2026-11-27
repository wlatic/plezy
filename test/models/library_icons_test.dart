import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/library_icons.dart';

MediaLibrary _library(String title, MediaKind kind) =>
    MediaLibrary(id: 'l', backend: MediaBackend.jellyfin, title: title, kind: kind, serverId: 's');

void main() {
  test('themed libraries start with an icon that fits their name', () {
    expect(LibraryIcons.defaultFor(_library('🌙 Sleep', MediaKind.show)), Symbols.bedtime_rounded);
    expect(LibraryIcons.defaultFor(_library('Anime', MediaKind.show)), Symbols.auto_awesome_rounded);
    expect(LibraryIcons.defaultFor(_library('Movies', MediaKind.movie)), Symbols.movie_rounded);
    expect(LibraryIcons.defaultFor(_library('Shows', MediaKind.show)), Symbols.tv_rounded);
  });

  test('a saved choice wins, "none" shows the name only, unknown ids fall back', () {
    final shows = _library('Shows', MediaKind.show);
    expect(LibraryIcons.resolve(shows, 'scifi'), Symbols.rocket_launch_rounded);
    expect(LibraryIcons.resolve(shows, LibraryIcons.none), isNull);
    expect(LibraryIcons.resolve(shows, 'removed-in-a-later-version'), Symbols.tv_rounded);
    expect(LibraryIcons.resolve(shows, null), Symbols.tv_rounded);
  });

  test('icon ids are unique', () {
    final ids = LibraryIcons.choices.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, isNot(contains(LibraryIcons.none)));
  });
}
