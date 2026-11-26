import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/screens/libraries/libraries_screen.dart';

void main() {
  MediaLibrary library(MediaKind kind) =>
      MediaLibrary(id: 'lib1', backend: MediaBackend.jellyfin, title: 'Shows', kind: kind, serverId: 'srv');

  test('Explore follows Recommended only when switched on', () {
    final shows = library(MediaKind.show);
    expect(visibleLibraryTabs(shows).contains(LibraryTabType.explore), isFalse);
    final withExplore = visibleLibraryTabs(shows, explore: true);
    expect(withExplore.take(2), [LibraryTabType.recommended, LibraryTabType.explore]);
  });
}
