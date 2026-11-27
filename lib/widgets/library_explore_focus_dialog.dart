import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_kind.dart';
import '../models/library_explore_focus.dart';
import '../utils/dialogs.dart';
import 'app_icon.dart';

/// The outcome of [showLibraryExploreFocusDialog]: a focus to save, or
/// [cleared] to go back to the library's usual Explore rows.
class LibraryExploreFocusChoice {
  const LibraryExploreFocusChoice(this.focus);

  static const cleared = LibraryExploreFocusChoice(null);

  final LibraryExploreFocus? focus;
}

/// Lets the user pick what [libraryTitle]'s Explore tab explores: shows or
/// movies, and which genres. Null when cancelled.
Future<LibraryExploreFocusChoice?> showLibraryExploreFocusDialog(
  BuildContext context, {
  required String libraryTitle,
  required MediaKind libraryKind,
  LibraryExploreFocus? current,
}) => showScopedDialog<LibraryExploreFocusChoice>(
  context: context,
  builder: (context) => _ExploreFocusDialog(
    libraryTitle: libraryTitle,
    initialKind: current?.kind ?? (libraryKind == MediaKind.movie ? MediaKind.movie : MediaKind.show),
    initialGenres: current?.genres ?? const [],
    hasCurrent: current != null,
  ),
);

class _ExploreFocusDialog extends StatefulWidget {
  const _ExploreFocusDialog({
    required this.libraryTitle,
    required this.initialKind,
    required this.initialGenres,
    required this.hasCurrent,
  });

  final String libraryTitle;
  final MediaKind initialKind;
  final List<int> initialGenres;
  final bool hasCurrent;

  @override
  State<_ExploreFocusDialog> createState() => _ExploreFocusDialogState();
}

class _ExploreFocusDialogState extends State<_ExploreFocusDialog> {
  late MediaKind _kind = widget.initialKind;
  late final Set<int> _genres = {...widget.initialGenres};

  void _setKind(MediaKind kind) => setState(() {
    if (kind == _kind) return;
    _kind = kind;
    // Keep the genres both kinds share (Documentary, Comedy, ...).
    _genres.removeWhere((g) => !TmdbGenres.of(kind).containsKey(g));
  });

  @override
  Widget build(BuildContext context) {
    final genres = TmdbGenres.of(_kind);
    Widget kindTile(MediaKind kind, String label, IconData icon) => ListTile(
      autofocus: kind == _kind,
      leading: AppIcon(icon, fill: 1),
      title: Text(label),
      trailing: AppIcon(kind == _kind ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded),
      onTap: () => _setKind(kind),
    );

    return AlertDialog(
      title: Text('What should ${widget.libraryTitle} explore?'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: ListView(
          children: [
            Text(
              'Explore shows titles from these genres that you do not have yet, '
              'instead of the usual picks.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            kindTile(MediaKind.show, 'Shows', Symbols.tv_rounded),
            kindTile(MediaKind.movie, 'Movies', Symbols.movie_rounded),
            const Divider(),
            for (final entry in genres.entries)
              CheckboxListTile(
                value: _genres.contains(entry.key),
                title: Text(entry.value),
                onChanged: (on) => setState(() => on == true ? _genres.add(entry.key) : _genres.remove(entry.key)),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.hasCurrent)
          TextButton(
            onPressed: () => Navigator.pop(context, LibraryExploreFocusChoice.cleared),
            child: const Text('Use the usual picks'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _genres.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  LibraryExploreFocusChoice(
                    LibraryExploreFocus(
                      kind: _kind,
                      // Keep the list's order, not the order they were ticked.
                      genres: [
                        for (final g in genres.keys)
                          if (_genres.contains(g)) g,
                      ],
                    ),
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
