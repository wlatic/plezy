import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/library_explore_focus.dart';

void main() {
  test('a focus survives saving and reading', () {
    const focus = LibraryExploreFocus(kind: MediaKind.show, genres: [99, 10764]);
    final read = LibraryExploreFocus.parse(focus.encode())!;
    expect(read.kind, MediaKind.show);
    expect(read.genres, [99, 10764]);
  });

  test('cleared, corrupt or unknown-genre focus reads as none', () {
    expect(LibraryExploreFocus.parse(''), isNull);
    expect(LibraryExploreFocus.parse(null), isNull);
    expect(LibraryExploreFocus.parse('not json'), isNull);
    // 36 (History) is a movie genre only.
    expect(LibraryExploreFocus.parse('{"kind":"show","genres":[36]}'), isNull);
    expect(LibraryExploreFocus.parse('{"kind":"movie","genres":[36,123456]}')!.genres, [36]);
  });
}
