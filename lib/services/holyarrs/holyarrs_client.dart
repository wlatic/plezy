import 'dart:convert';

import 'package:http/http.dart' as http;

/// A HolyArrs (https://github.com/HolyArrs/HolyArrs) connection: the server
/// and a personal API key, which acts as the person who made it.
class HolyArrsCredentials {
  const HolyArrsCredentials({required this.baseUrl, required this.apiKey, this.displayName});

  final String baseUrl;
  final String apiKey;
  final String? displayName;

  HolyArrsCredentials copyWith({String? apiKey, String? displayName}) => HolyArrsCredentials(
    baseUrl: baseUrl,
    apiKey: apiKey ?? this.apiKey,
    displayName: displayName ?? this.displayName,
  );

  Map<String, Object?> toJson() => {'baseUrl': baseUrl, 'apiKey': apiKey, 'displayName': displayName};

  static HolyArrsCredentials? fromJson(Object? json) {
    if (json is! Map) return null;
    final baseUrl = json['baseUrl'], apiKey = json['apiKey'];
    if (baseUrl is! String || apiKey is! String || baseUrl.isEmpty) return null;
    return HolyArrsCredentials(baseUrl: baseUrl, apiKey: apiKey, displayName: json['displayName'] as String?);
  }
}

class HolyArrsException implements Exception {
  HolyArrsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// HolyArrs turns whole parts (such as Requests) off; it answers 409.
  bool get isPartOff => statusCode == 409;

  @override
  String toString() => message;
}

/// One title as HolyArrs's Explore and search show it.
class HolyArrsTitle {
  const HolyArrsTitle({
    required this.tmdbId,
    required this.kind,
    required this.name,
    this.year,
    this.poster,
    this.backdrop,
    this.overview,
    this.genres = const [],
    this.inLibrary = false,
    this.askState,
    this.askLabel,
    this.trailerKey,
    this.logo,
  });

  final int tmdbId;

  /// `movie` or `show`.
  final String kind;
  final String name;
  final int? year;
  final String? poster;
  final String? backdrop;
  final String? overview;
  final List<String> genres;
  final bool inLibrary;

  /// The household's request for the title, or null when nobody asked:
  /// HolyArrs's state code and its own wording for it.
  final String? askState;
  final String? askLabel;
  final String? trailerKey;
  final String? logo;

  static HolyArrsTitle? fromJson(Object? json) {
    if (json is! Map) return null;
    final tmdb = int.tryParse('${json['tmdb_id'] ?? ''}');
    final kind = json['kind'];
    final name = json['name'];
    if (tmdb == null || (kind != 'movie' && kind != 'show') || name is! String) return null;
    final ask = json['ask'];
    return HolyArrsTitle(
      tmdbId: tmdb,
      kind: kind as String,
      name: name,
      year: json['year'] is int ? json['year'] as int : null,
      poster: json['poster'] as String?,
      backdrop: json['backdrop'] as String?,
      overview: json['overview'] as String?,
      genres: [for (final g in (json['genres'] as List? ?? const [])) '$g'],
      inLibrary: json['in_library'] == true,
      askState: ask is Map ? ask['state']?.toString() : null,
      askLabel: ask is Map ? ask['state_label']?.toString() : null,
      trailerKey: json['trailer_key'] as String?,
      logo: json['card_logo'] as String?,
    );
  }
}

/// A title's full page: the card fields plus runtime, score, people and
/// similar titles.
class HolyArrsTitleDetail {
  const HolyArrsTitleDetail({
    required this.title,
    this.runtimeMinutes,
    this.certification,
    this.score,
    this.votes,
    this.people = const [],
    this.similar = const [],
  });

  final HolyArrsTitle title;
  final int? runtimeMinutes;
  final String? certification;

  /// Out of 10.
  final double? score;
  final int? votes;
  final List<({String name, String? character, String? photo})> people;
  final List<HolyArrsTitle> similar;

  static HolyArrsTitleDetail? fromJson(Object? json) {
    if (json is! Map) return null;
    final videos = json['videos'];
    final trailer = videos is List
        ? videos.whereType<Map>().where((v) => v['type'] == 'Trailer' && v['key'] is String).firstOrNull
        : null;
    final title = HolyArrsTitle.fromJson({
      ...json.cast<String, Object?>(),
      'trailer_key': ?(json['trailer_key'] ?? trailer?['key']),
      'card_logo': ?(json['card_logo'] ?? json['logo']),
    });
    if (title == null) return null;
    final score = json['score'];
    final rating = json['rating'];
    return HolyArrsTitleDetail(
      title: title,
      runtimeMinutes: json['runtime_minutes'] is int ? json['runtime_minutes'] as int : null,
      certification: rating is String && rating.isNotEmpty && rating != 'NR' ? rating : null,
      score: score is num && score > 0 ? score.toDouble() : null,
      votes: json['votes'] is int ? json['votes'] as int : null,
      people: [
        for (final person in (json['people'] as List? ?? const []))
          if (person is Map && person['name'] is String && person['role'] == 'actor')
            (
              name: person['name'] as String,
              character: person['character'] as String?,
              photo: person['profile'] as String?,
            ),
      ],
      similar: [
        for (final item in (json['similar'] as List? ?? const []))
          if (HolyArrsTitle.fromJson(item) case final HolyArrsTitle similar) similar,
      ],
    );
  }
}

/// One Explore row.
class HolyArrsRow {
  const HolyArrsRow({required this.id, required this.title, required this.items});

  final String id;
  final String title;
  final List<HolyArrsTitle> items;
}

/// The person's weekly request allowance; a null count means no limit.
class HolyArrsAskLimit {
  const HolyArrsAskLimit({this.moviesLeft, this.showsLeft});

  final int? moviesLeft;
  final int? showsLeft;

  int? leftFor({required bool isShow}) => isShow ? showsLeft : moviesLeft;
}

/// Minimal HolyArrs API client for Explore, search and requests.
class HolyArrsClient {
  HolyArrsClient(this.credentials, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final HolyArrsCredentials credentials;
  final http.Client _http;

  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${credentials.baseUrl}$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
    'X-Api-Key': credentials.apiKey,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Future<Object?> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final request = http.Request(method, _uri(path, query))..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 30)));
    return _decode(response);
  }

  static Object? _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return json;
    final message = json is Map ? (json['text'] ?? json['error'])?.toString() : null;
    throw HolyArrsException(message ?? 'HolyArrs answered ${response.statusCode}', statusCode: response.statusCode);
  }

  /// Who the key belongs to; also checks the address and key work.
  Future<String> whoAmI() async {
    final me = await _send('GET', '/api/v1/auth/me');
    final name = me is Map ? me['name'] : null;
    if (name is! String) throw HolyArrsException('HolyArrs did not say who this key belongs to');
    return name;
  }

  /// Explore's rows for `movies` or `shows`, personalised for the key's person.
  Future<List<HolyArrsRow>> exploreRows(String type) async {
    final data = await _send('GET', '/api/v1/explore/head', query: {'type': type});
    final head = data is Map ? data['head'] : null;
    if (head is! List) return const [];
    return [
      for (final row in head)
        if (row is Map && row['id'] is String && row['title'] is String)
          HolyArrsRow(
            id: row['id'] as String,
            title: row['title'] as String,
            items: [
              for (final item in (row['items'] as List? ?? const []))
                if (HolyArrsTitle.fromJson(item) case final HolyArrsTitle title) title,
            ],
          ),
    ];
  }

  static List<HolyArrsRow> _rows(Object? rows) => rows is! List
      ? const []
      : [
          for (final row in rows)
            if (row is Map && row['id'] is String && row['title'] is String)
              HolyArrsRow(
                id: row['id'] as String,
                title: row['title'] as String,
                items: [
                  for (final item in (row['items'] as List? ?? const []))
                    if (HolyArrsTitle.fromJson(item) case final HolyArrsTitle title) title,
                ],
              ),
        ];

  /// Each streaming service's top 10 today in [region] (a country code),
  /// for `all`, `movies` or `shows`, as "Top 10 on Netflix" rows.
  Future<List<HolyArrsRow>> serviceTops(String type, {required String region}) async {
    final data = await _send('GET', '/api/v1/explore/service-top', query: {'type': type, 'region': region});
    final services = data is Map ? data['services'] : null;
    if (services is! List) return const [];
    return [
      for (final service in services)
        if (service is Map && service['key'] is String && service['name'] is String)
          HolyArrsRow(
            id: 'top:${service['key']}',
            title: 'Top 10 on ${service['name']}',
            items: [
              for (final item in (service['items'] as List? ?? const []))
                if (HolyArrsTitle.fromJson(item) case final HolyArrsTitle title) title,
            ],
          ),
    ];
  }

  /// The New & Popular page's rows (Critically acclaimed new releases, ...).
  Future<List<HolyArrsRow>> newRows(String type) async {
    final data = await _send('GET', '/api/v1/explore/new', query: {'type': type});
    return _rows(data is Map ? data['rows'] : null);
  }

  /// Explore's generated rows after the head (More from an actor, decades,
  /// Because you have ...), four per [page].
  Future<List<HolyArrsRow>> tailRows(String type, {int page = 0}) async {
    final data = await _send('GET', '/api/v1/explore/tail', query: {'type': type, 'page': '$page'});
    return _rows(data is Map ? data['rows'] : null);
  }

  /// The Browse strip's themed lists for [type] (Holiday, Based on a true
  /// story, Award winners, ...) as (category id, name), skipping plain genres.
  Future<List<({String id, String name})>> browseCategories(String type) async {
    final data = await _send('GET', '/api/v1/explore/strip', query: {'type': type});
    final tiles = data is Map ? data['tiles'] : null;
    if (tiles is! List) return const [];
    return [
      for (final tile in tiles)
        if (tile is Map &&
            tile['category'] is String &&
            (tile['category'] as String).isNotEmpty &&
            tile['name'] is String)
          (id: tile['category'] as String, name: tile['name'] as String),
    ];
  }

  /// One themed list's titles, most popular first.
  Future<HolyArrsRow> browseCategory(String type, ({String id, String name}) category) async {
    final data = await _send('GET', '/api/v1/explore/browse/category', query: {'type': type, 'id': category.id});
    return HolyArrsRow(
      id: 'list:${category.id}',
      title: data is Map && data['name'] is String ? data['name'] as String : category.name,
      items: [
        for (final item in (data is Map ? data['items'] as List? ?? const [] : const []))
          if (HolyArrsTitle.fromJson(item) case final HolyArrsTitle title) title,
      ],
    );
  }

  /// HolyArrs's page for one TMDB genre of `movies` or `shows`: Trending,
  /// Best new, Because you have, Top-rated classics and mood rows.
  Future<List<HolyArrsRow>> genreRows(String type, int genreId) async {
    final data = await _send('GET', '/api/v1/explore/genre', query: {'type': type, 'genre': '$genreId'});
    final rows = data is Map ? data['rows'] : null;
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && row['id'] is String && row['title'] is String)
          HolyArrsRow(
            id: row['id'] as String,
            title: row['title'] as String,
            items: [
              for (final item in (row['items'] as List? ?? const []))
                if (HolyArrsTitle.fromJson(item) case final HolyArrsTitle title) title,
            ],
          ),
    ];
  }

  /// A movie's or show's full details, from HolyArrs's TMDB cache.
  Future<HolyArrsTitleDetail?> titleDetail({required int tmdbId, required bool isShow}) async {
    final data = await _send('GET', '/api/v1/metadata/${isShow ? 'show' : 'movie'}/$tmdbId');
    return HolyArrsTitleDetail.fromJson(data);
  }

  /// Titles matching [query], as HolyArrs's own search box finds them
  /// (by name, library and not), plus any extra titles a descriptive query
  /// such as "space movie with a robot" turns up.
  Future<List<HolyArrsTitle>> search(String query) async {
    final results = await Future.wait([
      _send('GET', '/api/v1/search/suggest', query: {'q': query}),
      _send('GET', '/api/v1/search', query: {'q': query}).catchError((_) => null),
    ]);
    final suggest = results[0], plain = results[1];
    final seen = <int>{};
    final titles = <HolyArrsTitle>[];
    void add(HolyArrsTitle? title) {
      if (title != null && seen.add(title.tmdbId)) titles.add(title);
    }

    if (suggest is Map) {
      for (final row in (suggest['items'] as List? ?? const [])) {
        if (row is! Map) continue;
        final state = row['state'];
        add(
          HolyArrsTitle.fromJson({
            'tmdb_id': row['tmdb'],
            'kind': row['kind'],
            'name': row['name'],
            'year': int.tryParse(RegExp(r'\b(?:19|20)\d{2}\b').firstMatch('${row['sub'] ?? ''}')?.group(0) ?? ''),
            'poster': row['art'],
            'in_library': state == 'have',
            'ask': state == 'asked' ? {'state': 'asked'} : null,
          }),
        );
      }
    }
    if (plain is Map) {
      for (final item in (plain['more'] as List? ?? const [])) {
        add(HolyArrsTitle.fromJson(item));
      }
    }
    return titles;
  }

  /// Ask for a movie, or a show's [seasons] (empty asks for the whole show).
  Future<void> ask({
    required int tmdbId,
    required bool isShow,
    List<int> seasons = const [],
    bool futureOnly = false,
  }) async {
    await _send(
      'POST',
      '/api/v1/asks',
      body: {
        'id': 'tmdb:$tmdbId',
        'kind': isShow ? 'show' : 'movie',
        if (isShow && seasons.isNotEmpty) 'seasons': seasons,
        if (isShow && futureOnly) 'future_only': true,
      },
    );
  }

  /// The person's weekly allowance; null when HolyArrs sets no limit.
  Future<HolyArrsAskLimit?> askLimit() async {
    final data = await _send('GET', '/api/v1/asks/limit');
    if (data is! Map) return null;
    if (data['no_limit'] == true) return const HolyArrsAskLimit();
    int? left(String kind) {
      final entry = data[kind];
      if (entry is! Map || entry['no_limit'] == true || entry['per_week'] == 0) return null;
      return entry['left'] is int ? entry['left'] as int : null;
    }

    return HolyArrsAskLimit(moviesLeft: left('movies'), showsLeft: left('shows'));
  }

  /// Sign in with a HolyArrs password or (when HolyArrs allows it) through
  /// Jellyfin, then make a personal API key for this app and sign the
  /// session out again. Only the key is kept.
  static Future<HolyArrsCredentials> signIn({
    required String baseUrl,
    required String name,
    required String password,
    required bool throughJellyfin,
    required String keyLabel,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final base = normalizeBaseUrl(baseUrl);
    final loginPath = throughJellyfin ? '/api/v1/auth/media-server/jellyfin' : '/api/v1/auth/login';
    final login = await client.post(
      Uri.parse('$base$loginPath'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'name': name, 'password': password}),
    );
    _decode(login);
    final cookie = login.headers['set-cookie']?.split(';').first;
    if (cookie == null) throw HolyArrsException('HolyArrs did not start a session');
    final sessionHeaders = {'Cookie': cookie, 'Accept': 'application/json', 'Content-Type': 'application/json'};
    final me = _decode(await client.get(Uri.parse('$base/api/v1/auth/me'), headers: sessionHeaders));
    final csrf = me is Map ? me['csrf'] as String? : null;
    final displayName = me is Map ? me['name'] as String? : null;
    final made = _decode(
      await client.post(
        Uri.parse('$base/api/v1/auth/keys'),
        headers: {...sessionHeaders, 'X-CSRF-Token': ?csrf},
        body: jsonEncode({
          'label': keyLabel,
          'scopes': ['all'],
        }),
      ),
    );
    final key = made is Map ? made['key'] as String? : null;
    try {
      await client.post(Uri.parse('$base/api/v1/auth/logout'), headers: {...sessionHeaders, 'X-CSRF-Token': ?csrf});
    } catch (_) {}
    if (key == null || key.isEmpty) throw HolyArrsException('HolyArrs did not hand out an API key');
    return HolyArrsCredentials(baseUrl: base, apiKey: key, displayName: displayName);
  }
}
