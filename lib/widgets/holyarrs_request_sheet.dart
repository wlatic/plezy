import 'package:flutter/material.dart';

import '../media/media_kind.dart';
import '../services/catalog/holyarrs_catalog_source.dart';
import '../services/holyarrs/holyarrs_client.dart';
import '../utils/dialogs.dart';
import '../utils/snackbar_helper.dart';

/// Ask HolyArrs for a movie, or a show (whole show or new seasons only),
/// showing the person's weekly allowance.
Future<void> showHolyArrsRequestSheet(
  BuildContext context, {
  required HolyArrsCatalogSource source,
  required MediaKind kind,
  required int tmdbId,
  required String title,
}) async {
  final requested = await showScopedDialog<bool>(
    context: context,
    builder: (context) => _HolyArrsRequestDialog(source: source, kind: kind, tmdbId: tmdbId, title: title),
  );
  if (requested == true && context.mounted) {
    showSuccessSnackBar(context, 'Requested $title. It is waiting for approval in HolyArrs.');
  }
}

class _HolyArrsRequestDialog extends StatefulWidget {
  const _HolyArrsRequestDialog({required this.source, required this.kind, required this.tmdbId, required this.title});

  final HolyArrsCatalogSource source;
  final MediaKind kind;
  final int tmdbId;
  final String title;

  @override
  State<_HolyArrsRequestDialog> createState() => _HolyArrsRequestDialogState();
}

class _HolyArrsRequestDialogState extends State<_HolyArrsRequestDialog> {
  bool get _isShow => widget.kind == MediaKind.show;
  var _newSeasonsOnly = false;
  var _busy = false;
  String? _error;
  String? _allowance;

  @override
  void initState() {
    super.initState();
    _loadAllowance();
  }

  Future<void> _loadAllowance() async {
    try {
      final limit = await widget.source.client.askLimit();
      final left = limit?.leftFor(isShow: _isShow);
      if (!mounted) return;
      setState(() {
        _allowance = left == null
            ? 'No weekly limit'
            : '$left ${_isShow ? 'show' : 'movie'} request${left == 1 ? '' : 's'} left this week';
      });
    } on HolyArrsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // The allowance is informational; asking still reports a refusal.
    }
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.client.ask(tmdbId: widget.tmdbId, isShow: _isShow, futureOnly: _newSeasonsOnly);
      if (mounted) Navigator.of(context).pop(true);
    } on HolyArrsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach HolyArrs: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Request ${widget.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isShow)
            RadioGroup<bool>(
              groupValue: _newSeasonsOnly,
              onChanged: (v) {
                if (!_busy) setState(() => _newSeasonsOnly = v ?? false);
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(value: false, title: Text('Whole show')),
                  RadioListTile<bool>(
                    value: true,
                    title: Text('New seasons only'),
                    subtitle: Text('Seasons and episodes that air from now on'),
                  ),
                ],
              ),
            ),
          if (_allowance != null) Text(_allowance!, style: theme.textTheme.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(autofocus: true, onPressed: _busy ? null : _request, child: const Text('Request')),
      ],
    );
  }
}
