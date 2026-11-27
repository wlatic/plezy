import 'dart:convert';

import '../media/media_kind.dart';

/// What a library's Explore tab explores instead of its general rows: one
/// kind and one or more TMDB genres (a Sleep library exploring documentary
/// shows, say). Saved per library next to its row settings.
class LibraryExploreFocus {
  const LibraryExploreFocus({required this.kind, required this.genres});

  final MediaKind kind;
  final List<int> genres;

  bool get isEmpty => genres.isEmpty;

  String encode() => jsonEncode({'kind': kind == MediaKind.movie ? 'movie' : 'show', 'genres': genres});

  static LibraryExploreFocus? parse(String? saved) {
    if (saved == null || saved.isEmpty) return null;
    try {
      final value = jsonDecode(saved);
      if (value is! Map) return null;
      final kind = value['kind'] == 'movie' ? MediaKind.movie : MediaKind.show;
      final genres = [
        for (final g in (value['genres'] as List? ?? const []))
          if (g is int && TmdbGenres.of(kind).containsKey(g)) g,
      ];
      return genres.isEmpty ? null : LibraryExploreFocus(kind: kind, genres: genres);
    } on FormatException {
      return null;
    }
  }
}

/// TMDB's genre ids, which HolyArrs and Seerr both filter by.
abstract final class TmdbGenres {
  static const shows = <int, String>{
    99: 'Documentary',
    10764: 'Reality',
    35: 'Comedy',
    18: 'Drama',
    80: 'Crime',
    9648: 'Mystery',
    10759: 'Action & Adventure',
    10765: 'Sci-Fi & Fantasy',
    16: 'Animation',
    10751: 'Family',
    10762: 'Kids',
    10763: 'News',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War & Politics',
    37: 'Western',
  };

  static const movies = <int, String>{
    99: 'Documentary',
    36: 'History',
    10402: 'Music',
    35: 'Comedy',
    18: 'Drama',
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    80: 'Crime',
    10751: 'Family',
    14: 'Fantasy',
    27: 'Horror',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Science Fiction',
    53: 'Thriller',
    10770: 'TV Movie',
    10752: 'War',
    37: 'Western',
  };

  static Map<int, String> of(MediaKind kind) => kind == MediaKind.movie ? movies : shows;
}
