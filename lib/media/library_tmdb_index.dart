import 'dart:async';

import 'media_kind.dart';

/// The TMDB ids of the movies and shows a media server already has, so
/// outside catalog rows (HolyArrs) can mark titles as available without a
/// per-title lookup.
class LibraryTmdbIndex {
  const LibraryTmdbIndex({this.movies = const {}, this.shows = const {}});

  final Set<int> movies;
  final Set<int> shows;

  bool has(MediaKind kind, int tmdbId) => switch (kind) {
    MediaKind.movie => movies.contains(tmdbId),
    MediaKind.show => shows.contains(tmdbId),
    _ => false,
  };

  LibraryTmdbIndex merge(LibraryTmdbIndex other) =>
      LibraryTmdbIndex(movies: {...movies, ...other.movies}, shows: {...shows, ...other.shows});
}

/// A media server client that can list its library's TMDB ids in one call.
abstract interface class LibraryTmdbIndexClient {
  Future<LibraryTmdbIndex> fetchLibraryTmdbIndex();
}

typedef LibraryTmdbIndexLoader = Future<LibraryTmdbIndex?> Function();

/// Keeps one index for [ttl] and shares a load already in flight. A failed
/// load is not cached, so the next caller tries again.
class CachedLibraryTmdbIndex {
  CachedLibraryTmdbIndex(this._load, {this.ttl = const Duration(minutes: 10), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LibraryTmdbIndexLoader _load;
  final Duration ttl;
  final DateTime Function() _now;
  LibraryTmdbIndex? _index;
  DateTime? _loadedAt;
  Future<LibraryTmdbIndex?>? _inFlight;

  Future<LibraryTmdbIndex?> get() {
    final loadedAt = _loadedAt;
    if (_index != null && loadedAt != null && _now().difference(loadedAt) < ttl) return Future.value(_index);
    return _inFlight ??= _refresh();
  }

  Future<LibraryTmdbIndex?> _refresh() async {
    try {
      final index = await _load();
      if (index != null) {
        _index = index;
        _loadedAt = _now();
      }
      return index ?? _index;
    } catch (_) {
      return _index;
    } finally {
      _inFlight = null;
    }
  }
}
