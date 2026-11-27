import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../focus/hub_vertical_navigation.dart';
import '../../../focus/locked_hub_controller.dart';
import '../../../media/ids.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/server_home_rows_client.dart';
import '../../../media/library_row_settings_client.dart';
import '../../../models/library_explore_focus.dart';
import '../../../models/catalog/catalog_item.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../providers/explore_provider.dart';
import '../../../services/catalog/catalog_source.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/hub_section.dart';
import '../../../widgets/nested_tab_scrollbar.dart';
import '../../../widgets/tv_browse_rail.dart';
import '../../../widgets/tv_spotlight_scaffold.dart';
import '../../main_screen.dart';
import 'base_library_tab.dart';

/// Explore rows for one library: titles the library does not have yet, from
/// a source that fits it (AniList for an anime library, Seerr otherwise),
/// limited to the library's kind. Cards open the catalog detail screen with
/// its availability badges and Request button, as on the Explore screen.
class LibraryExploreTab extends BaseLibraryTab<MediaHub> {
  const LibraryExploreTab({
    super.key,
    required super.library,
    super.onDataLoaded,
    super.isActive,
    super.suppressAutoFocus,
    super.onBack,
    this.onNavigateToChrome,
  });

  final VoidCallback? onNavigateToChrome;

  @override
  State<LibraryExploreTab> createState() => _LibraryExploreTabState();
}

class _LibraryExploreTabState extends BaseLibraryTabState<MediaHub, LibraryExploreTab> {
  final Map<String, GlobalKey<HubSectionState>> _hubKeys = {};
  final _tvBrowseRailKey = GlobalKey<TvBrowseRailState>();
  final TvSpotlightController _spotlight = TvSpotlightController();
  final HubFocusMemory _hubFocusMemory = HubFocusMemory();

  @override
  void dispose() {
    _spotlight.dispose();
    super.dispose();
  }

  @override
  IconData get emptyIcon => Symbols.explore_rounded;

  @override
  String get emptyMessage =>
      'Connect HolyArrs or Seerr (or AniList for anime) in Settings to explore titles you do not have yet.';

  @override
  String get errorContext => 'Explore';

  bool get _isAnime => widget.library.kind == MediaKind.show && widget.library.title.toLowerCase().contains('anime');

  /// The source this library explores: an anime library prefers AniList,
  /// then MyAnimeList; everything falls back to Seerr.
  CatalogSource? _sourceFor(CatalogSourcesProvider sources) {
    final connected = {for (final source in sources.connectedSources) source.id: source};
    final order = _isAnime
        ? const [CatalogSourceId.anilist, CatalogSourceId.mal, CatalogSourceId.seerr]
        : const [CatalogSourceId.seerr];
    for (final id in order) {
      if (connected[id] case final CatalogSource source) return source;
    }
    return null;
  }

  @override
  Future<void> loadItems() => runLoadTransaction(_loadRows);

  Future<List<MediaHub>> _loadRows() async {
    final sources = context.read<CatalogSourcesProvider>();
    final kind = widget.library.kind;
    final serverId = widget.library.serverId;
    final serverClient = context.tryGetMediaClientForServer(serverIdOrNull(serverId));
    final focus = serverClient is LibraryRowSettingsClient
        ? await (serverClient as LibraryRowSettingsClient).fetchLibraryExploreFocus(widget.library.id)
        : null;
    if (focus != null && mounted) return _focusedRows(sources, focus);
    // HolyArrs's own Explore rows, already split into movies and shows.
    final holyarrs = sources.holyarrsSource;
    final holyarrsHubs = holyarrs == null || _isAnime
        ? null
        : await holyarrs
              .fetchKindHubs(kind, limit: ExploreProvider.rowLimit)
              .then<List<CatalogHub>?>((h) => h)
              .catchError((Object e) {
                // A revoked key or HolyArrs being down falls back to Seerr.
                appLogger.w('Library explore: HolyArrs rows failed', error: e);
                return null;
              });
    if (holyarrsHubs != null) {
      final hubs = holyarrsHubs;
      return [
        for (final hub in hubs)
          MediaHub(
            id: 'library-explore.${widget.library.id}.${hub.id}',
            identifier: 'library-explore.${widget.library.id}.${hub.id}',
            title: hub.title,
            type: 'mixed',
            items: [for (final item in hub.page.items) item.toMediaItem()],
            size: hub.page.items.length,
            more: false,
            serverId: serverId,
          ),
      ];
    }
    final source = _sourceFor(sources);
    if (source == null) return _serverDiscoverRows();

    MediaHub hub(String id, String title, List<CatalogItem> items) {
      final matching = [
        for (final item in items)
          if (item.kind == kind) item.toMediaItem(),
      ];
      return MediaHub(
        id: 'library-explore.${widget.library.id}.$id',
        identifier: 'library-explore.${widget.library.id}.$id',
        title: title,
        type: 'mixed',
        items: matching,
        size: matching.length,
        more: false,
        serverId: serverId,
      );
    }

    final hubs = <MediaHub>[];
    await Future.wait<void>([
      for (final row in source.supportedRows)
        if (row != CatalogRowId.watchlist)
          () async {
            try {
              final page = await source.fetchRow(row, limit: ExploreProvider.rowLimit);
              hubs.add(hub(row.name, ExploreProvider.rowTitle(row), page.items));
            } catch (e) {
              appLogger.w('Library explore: ${source.id.name} row ${row.name} failed', error: e);
            }
          }(),
    ]);
    // Keep the source's own row order rather than completion order.
    final order = [for (final row in source.supportedRows) 'library-explore.${widget.library.id}.${row.name}'];
    hubs.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
    return hubs.where((hub) => hub.items.isNotEmpty).toList();
  }

  /// The library's chosen kind and genres: HolyArrs's genre pages, or one
  /// popular row per genre from Seerr.
  Future<List<MediaHub>> _focusedRows(CatalogSourcesProvider sources, LibraryExploreFocus focus) async {
    MediaHub hub(String id, String title, List<CatalogItem> items) => MediaHub(
      id: 'library-explore.${widget.library.id}.$id',
      identifier: 'library-explore.${widget.library.id}.$id',
      title: title,
      type: 'mixed',
      items: [for (final item in items) item.toMediaItem()],
      size: items.length,
      more: false,
      serverId: widget.library.serverId,
    );

    final holyarrs = sources.holyarrsSource;
    if (holyarrs != null) {
      try {
        final hubs = await holyarrs.fetchGenreHubs(focus.kind, focus.genres, limit: ExploreProvider.rowLimit);
        return [for (final h in hubs) hub(h.id, h.title, h.page.items)];
      } catch (e) {
        // A revoked key or HolyArrs being down falls back to Seerr.
        appLogger.w('Library explore: HolyArrs genre rows failed', error: e);
      }
    }
    final seerr = sources.seerrSource;
    if (seerr == null) return const [];
    final names = TmdbGenres.of(focus.kind);
    final pages = await Future.wait([
      for (final genre in focus.genres)
        seerr.fetchGenre(focus.kind, genre).then<CatalogPage?>((p) => p).catchError((Object e) {
          appLogger.w('Library explore: Seerr genre $genre failed', error: e);
          return null;
        }),
    ]);
    return [
      for (var i = 0; i < focus.genres.length; i++)
        if (pages[i] case final CatalogPage page when page.items.isNotEmpty)
          hub('genre.${focus.genres[i]}', 'Popular ${names[focus.genres[i]] ?? ''}'.trim(), page.items),
    ];
  }

  /// With no request service connected in the app, the server's own
  /// Discover row (Home Screen Sections, through Seerr) still shows what is
  /// out there. Not for anime, which it does not cover.
  Future<List<MediaHub>> _serverDiscoverRows() async {
    if (_isAnime) return const [];
    final client = context.tryGetMediaClientForServer(serverIdOrNull(widget.library.serverId));
    if (client is! ServerHomeRowsClient) return const [];
    final hub = await (client as ServerHomeRowsClient).fetchServerDiscoverRow(
      widget.library.kind,
      limit: ExploreProvider.rowLimit,
    );
    if (hub == null || hub.items.isEmpty) return const [];
    return [
      MediaHub(
        id: 'library-explore.${widget.library.id}.server-discover',
        identifier: 'library-explore.${widget.library.id}.server-discover',
        title: hub.title,
        type: 'mixed',
        items: hub.items,
        size: hub.items.length,
        more: false,
        serverId: widget.library.serverId,
      ),
    ];
  }

  @override
  bool get hasFocusableContent => items.any((hub) => hub.items.isNotEmpty);

  @override
  void focusFirstItem() {
    if (PlatformDetector.isTV()) {
      final rail = _tvBrowseRailKey.currentState;
      if (rail != null) {
        rail.requestFocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final rail = _tvBrowseRailKey.currentState;
          if (rail != null) {
            rail.requestFocus();
          } else {
            focusEmptyState();
          }
        });
      }
      return;
    }
    if (items.isNotEmpty) _keyFor(items.first).currentState?.requestFocusAt(0);
  }

  GlobalKey<HubSectionState> _keyFor(MediaHub hub) => _hubKeys.putIfAbsent(hub.id, GlobalKey<HubSectionState>.new);

  void _navigateToSidebar() => MainScreenFocusScope.focusSidebarOf(context);

  @override
  Widget buildContent(List<MediaHub> items) {
    if (PlatformDetector.isTV()) {
      return TvSpotlightScaffold(
        hubs: items,
        spotlightListenable: _spotlight,
        resolveSpotlight: () => _spotlight.resolve(items),
        resolveClient: (spotlight) =>
            context.tryGetMediaClientForServer(serverIdOrNull(spotlight?.serverId ?? widget.library.serverId)),
        foreground: Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TvBrowseRail(
            key: _tvBrowseRailKey,
            hubs: items,
            focusMemory: _hubFocusMemory,
            iconForHub: (hub, _) => Symbols.explore_rounded,
            onFocusedItemChanged: (MediaItem item) => _spotlight.select(item),
            onNavigateUp: widget.onNavigateToChrome ?? widget.onBack,
            onNavigateToSidebar: _navigateToSidebar,
            onBack: widget.onBack,
            tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
            widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
          ),
        ),
      );
    }
    return NestedTabScrollbar(
      child: CustomScrollView(
        clipBehavior: Clip.none,
        slivers: [
          SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final hub = items[index];
                return HubSection(
                  key: _keyFor(hub),
                  hub: hub,
                  focusMemory: _hubFocusMemory,
                  icon: Symbols.explore_rounded,
                  onVerticalNavigation: (isUp) => navigateVerticalHubRows(
                    hubCount: items.length,
                    hubIndex: index,
                    isUp: isUp,
                    propagateTopBoundary: true,
                    requestFocus: (target) => _keyFor(items[target]).currentState?.requestFocusFromMemory(),
                  ),
                  onBack: widget.onBack,
                  onNavigateUp: index == 0 ? widget.onBack : null,
                  onNavigateToSidebar: _navigateToSidebar,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
