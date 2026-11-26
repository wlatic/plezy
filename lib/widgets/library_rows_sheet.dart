import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/dpad_reorder_mixin.dart';
import '../focus/focus_theme.dart';
import '../focus/input_mode_tracker.dart';
import '../media/library_row_settings_client.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../models/library_row_settings.dart';
import '../utils/app_logger.dart';
import '../utils/dialogs.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import 'app_icon.dart';
import 'bottom_sheet_page_scaffold.dart';
import 'overlay_sheet.dart';

/// Lets the user choose and order the rows of [library]'s Recommended tab.
/// Changes are saved to the server as they are made. Returns whether anything
/// changed, so the caller can reload the tab.
Future<bool> showLibraryRowsSheet(
  BuildContext context, {
  required MediaLibrary library,
  required LibraryRowSettingsClient client,
}) async {
  final kind = library.kind;
  final rows = await client.fetchLibraryRowSettings(library.id, kind);
  if (!context.mounted) return false;
  var changed = false;

  Future<void> save(List<LibraryRowSetting> updated) async {
    changed = true;
    try {
      await client.saveLibraryRowSettings(library.id, updated);
    } catch (e, st) {
      appLogger.w('Saving library rows failed', error: e, stackTrace: st);
      if (context.mounted) showErrorSnackBar(context, 'Could not save the row settings');
    }
  }

  Widget build({required bool isDialog}) =>
      _LibraryRowsSheet(title: '${library.title} rows', kind: kind, initial: rows, isDialog: isDialog, onChanged: save);

  if (PlatformDetector.isTV()) {
    await showScopedDialog<void>(context: context, builder: (context) => build(isDialog: true));
  } else {
    await OverlaySheetController.showAdaptive<void>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => build(isDialog: false),
    );
  }
  return changed;
}

class _LibraryRowsSheet extends StatefulWidget {
  const _LibraryRowsSheet({
    required this.title,
    required this.kind,
    required this.initial,
    required this.isDialog,
    required this.onChanged,
  });

  final String title;
  final MediaKind kind;
  final List<LibraryRowSetting> initial;
  final bool isDialog;
  final Future<void> Function(List<LibraryRowSetting> rows) onChanged;

  @override
  State<_LibraryRowsSheet> createState() => _LibraryRowsSheetState();
}

class _LibraryRowsSheetState extends State<_LibraryRowsSheet>
    with DpadReorderListMixin<LibraryRowSetting, _LibraryRowsSheet> {
  late List<LibraryRowSetting> _rows = List.of(widget.initial);
  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  List<LibraryRowSetting> get reorderItems => _rows;

  @override
  set reorderItems(List<LibraryRowSetting> value) => _rows = value;

  /// Column 0 moves the row, column 1 shows or hides it.
  @override
  int get lastReorderColumn => 1;

  @override
  ScrollController? get reorderScrollController => _scrollController;

  @override
  void onReorderMoveConfirmed() => unawaited(widget.onChanged(List.of(_rows)));

  @override
  void onReorderColumnActivated(int column, int index) {
    if (column == 1) _toggle(index);
  }

  void _toggle(int index) {
    setState(() => _rows[index] = _rows[index].copyWith(enabled: !_rows[index].enabled));
    unawaited(widget.onChanged(List.of(_rows)));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() => _rows.insert(newIndex, _rows.removeAt(oldIndex)));
    unawaited(widget.onChanged(List.of(_rows)));
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = Focus(
      focusNode: _listFocusNode,
      descendantsAreFocusable: false,
      autofocus: InputModeTracker.isKeyboardMode(context),
      onKeyEvent: handleReorderKeyEvent,
      child: _buildList(shrinkWrap: !widget.isDialog),
    );
    if (!widget.isDialog) {
      return BottomSheetPageScaffold(title: widget.title, icon: Symbols.view_list_rounded, child: list);
    }
    return Dialog(
      child: PopScope(
        canPop: false, // Back is handled by handleReorderKeyEvent so it does not double-pop.
        // ignore: no-empty-block - required callback, blocks system back on Android TV
        onPopInvokedWithResult: (didPop, result) {},
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const AppIcon(Symbols.view_list_rounded, fill: 1),
                const SizedBox(width: 12),
                Text(widget.title),
              ],
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const AppIcon(Symbols.close_rounded, fill: 1),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: list,
        ),
      ),
    );
  }

  Widget _buildList({required bool shrinkWrap}) {
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    return ReorderableListView.builder(
      scrollController: _scrollController,
      shrinkWrap: shrinkWrap,
      onReorderItem: _reorder,
      itemCount: _rows.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final isFocused = isKeyboardMode && index == focusedIndex;
        return _buildRowTile(
          _rows[index],
          index,
          isFocused: isFocused,
          isMoving: index == movingIndex,
          focusedColumn: isFocused ? focusedColumn : null,
        );
      },
    );
  }

  Widget _buildRowTile(
    LibraryRowSetting row,
    int index, {
    required bool isFocused,
    required bool isMoving,
    int? focusedColumn,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tileColor = isMoving
        ? colorScheme.primaryContainer
        : isFocused && focusedColumn == 0
        ? colorScheme.surfaceContainerHighest
        : null;
    return Opacity(
      key: ValueKey(row.id),
      opacity: row.enabled ? 1.0 : 0.5,
      child: ListTile(
        tileColor: tileColor,
        leading: ReorderableDragStartListener(
          index: index,
          child: AppIcon(
            isMoving ? Symbols.swap_vert_rounded : Symbols.drag_indicator_rounded,
            fill: 1,
            color: isMoving ? colorScheme.primary : IconTheme.of(context).color?.withValues(alpha: 0.5),
          ),
        ),
        title: Text(LibraryRows.title(row.id, widget.kind)),
        subtitle: row.enabled ? null : const Text('Hidden'),
        trailing: Container(
          decoration: FocusTheme.focusBackgroundDecoration(
            context,
            isFocused: isFocused && focusedColumn == 1,
            borderRadius: 20,
          ),
          child: IconButton(
            icon: AppIcon(row.enabled ? Symbols.visibility_rounded : Symbols.visibility_off_rounded, fill: 1),
            tooltip: row.enabled ? 'Hide row' : 'Show row',
            onPressed: () => _toggle(index),
          ),
        ),
      ),
    );
  }
}
