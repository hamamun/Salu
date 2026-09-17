import 'package:flutter/material.dart';

import '../../core/web/web_data_control.dart';
import '../../theme/app_theme.dart';

/// The Clear dialog — Chrome-shaped, SALU-skinned (web.md · Clear data —
/// LOCKED): exactly four checkboxes, all of it browser-owned data —
/// Browsing history · Cookies & site data · Cached images & files ·
/// Downloads. One button clears; there is no confirmation of a
/// confirmation — the dialog IS the confirmation, exactly once, like every
/// other modal SALU owns.
///
/// SALU's own data (resume memory, saved streams) is a different store and
/// is never mentioned here, because it is never touched (web.md lock).
Future<void> showWebClearDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => const _WebClearDialog(),
  );
}

class _WebClearDialog extends StatefulWidget {
  const _WebClearDialog();

  @override
  State<_WebClearDialog> createState() => _WebClearDialogState();
}

class _WebClearDialogState extends State<_WebClearDialog> {
  bool _history = true;
  bool _cookies = true;
  bool _cache = true;
  bool _downloads = false;
  bool _busy = false;

  Future<void> _clear() async {
    if (_busy) return;
    _busy = true;
    await WebDataControlService.instance.clear(WebDataClearFlags(
      history: _history,
      cookies: _cookies,
      cache: _cache,
      downloads: _downloads,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.surfaceOutline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Clear browsing data',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Everything here is SALU\'s browser footprint only — what '
              'you watch and where you left off is SALU\'s own memory, '
              'always safe.',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            _CheckRow(
              label: 'Browsing history',
              value: _history,
              onChanged: (bool v) => setState(() => _history = v),
            ),
            _CheckRow(
              label: 'Cookies & site data',
              value: _cookies,
              onChanged: (bool v) => setState(() => _cookies = v),
            ),
            _CheckRow(
              label: 'Cached images & files',
              value: _cache,
              onChanged: (bool v) => setState(() => _cache = v),
            ),
            _CheckRow(
              label: 'Downloads',
              value: _downloads,
              onChanged: (bool v) => setState(() => _downloads = v),
              note: 'The files stay on your PC — the browser forgets them.',
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _busy ? null : _clear,
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Clear data',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.note,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 32, height: 32,
              child: FittedBox(
                child: Checkbox(
                  value: value,
                  onChanged: (bool? v) => onChanged(v ?? false),
                  activeColor: AppColors.accent,
                  checkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textPrimary),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
