import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings_service.dart';
import '../../core/ui_lock.dart';
import '../../core/updater/update_installer_windows.dart';
import '../../core/updater/update_manifest.dart';
import '../../core/updater/updater_service.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// SALU's compact updater modal (updater.md §8) — the dialog behind
/// Settings → Updates → "Check now", over the same dimmed glass backdrop
/// as the rest of SALU's focus tasks (follow.md §1 · modal vs panel).
///
/// The state machine is updater.md §8's layout flow exactly:
/// **checking** → **updatesFound** (Cancel / Update) → **downloading**
/// (live progress + Cancel) → **readyToRestart** (Restart Later / Restart
/// Now); or **upToDate** (Close) / **failed** (a message matched to the
/// check, download, preparation or installation failure).
Future<void> showUpdateDialog(BuildContext context) {
  ChromeLock.instance.acquire();
  return showGeneralDialog<void>(
    context: context,
    barrierColor: const Color(0x99000000),
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final CurvedAnimation curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) =>
        const _UpdateDialog(),
  ).whenComplete(ChromeLock.instance.release);
}

enum _UpdateStage {
  /// State 1 — the feeds are being asked.
  checking,

  /// State 2A — rows with upgrade arrows; the Update door is open.
  updatesFound,

  /// State 2B — everything already runs the newest version.
  upToDate,

  /// State 2C — streaming payloads into `%TEMP%\salu_update\`.
  downloading,

  /// State 2D — staged and verified; the swap needs a restart.
  readyToRestart,

  /// A check, download, preparation or installer failure.
  failed,
}

/// A failed download is different from a downloaded file that could not be
/// verified or unpacked. Only network failures should mention connectivity.
enum _UpdateFailureKind { check, download, preparation, installation }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdateStage _stage = _UpdateStage.checking;
  UpdateCheckResult? _result;
  UpdateProgress? _lastProgress;

  /// Set the moment any close path leaves the dialog — the in-flight
  /// download sees it, aborts its stream and purges staging (updater.md
  /// §8's mid-download Cancel rules), whichever button (or barrier tap)
  /// did it.
  bool _cancelRequested = false;

  /// A little safe, user-readable error context for the failed state.
  _UpdateFailureKind _failureKind = _UpdateFailureKind.check;
  String? _failureDetail;

  UpdaterService get _updater => UpdaterService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_runCheck());
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _runCheck() async {
    final UpdateCheckResult result = await _updater.check();
    if (!mounted) return;
    setState(() {
      _result = result;
      if (!result.ok) {
        _failureKind = _UpdateFailureKind.check;
        _failureDetail = null;
        _stage = _UpdateStage.failed;
      } else if (result.hasUpdates) {
        _stage = _UpdateStage.updatesFound;
      } else {
        _stage = _UpdateStage.upToDate;
      }
    });
  }

  Future<void> _startDownload() async {
    final UpdateCheckResult? result = _result;
    if (result == null) return;
    final List<ComponentUpdate> updates = result.pendingUpdates;
    setState(() => _stage = _UpdateStage.downloading);
    try {
      await _updater.download(
        updates,
        onProgress: (UpdateProgress progress) {
          if (!mounted) return;
          setState(() => _lastProgress = progress);
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() => _stage = _UpdateStage.readyToRestart);
    } on UpdateCancelledException {
      // Already closed (or closing) — staging is already purged.
    } on UpdateFetchException {
      _showFailure(_UpdateFailureKind.download);
    } on UpdateVerifyException catch (error) {
      // Only known verification messages are safe to display. Never show
      // an exception class, URL or a raw OS error to the user.
      _showFailure(_UpdateFailureKind.preparation, detail: error.message);
    } catch (error) {
      debugPrint('[SALU] updater: preparation failed: $error');
      _showFailure(_UpdateFailureKind.preparation);
    }
  }

  void _showFailure(_UpdateFailureKind kind, {String? detail}) {
    if (!mounted) return;
    setState(() {
      _failureKind = kind;
      _failureDetail = detail;
      _stage = _UpdateStage.failed;
    });
  }

  /// Cancel / ✕ / barrier: close at once. Mid-download the dispose flag
  /// aborts the stream; the button below adds it eagerly so the abort
  /// starts before the route even finishes popping.
  void _close() {
    _cancelRequested = true;
    Navigator.of(context).pop();
  }

  Future<void> _restartNow() async {
    _cancelRequested = false; // the staging must SURVIVE this close
    try {
      final bool started = await _updater.restartNow();
      // exit(0) lands inside restartNow on Windows; a refused spawn stays
      // visible instead of pretending the swap is happening.
      if (!started) {
        _showFailure(
          _UpdateFailureKind.installation,
          detail: 'The updater script could not be started. The staged '
              'files are untouched - closing SALU will try again.',
        );
      }
    } on UpdateSwapRefusedException catch (error) {
      // A swap that cannot work where SALU is installed (a protected folder,
      // or one already running). Said plainly, and SALU keeps running.
      _showFailure(_UpdateFailureKind.installation, detail: error.message);
    } catch (error) {
      debugPrint('[SALU] updater: could not start installer: $error');
      _showFailure(_UpdateFailureKind.installation);
    }
  }

  void _restartLater() {
    // updater.md §8: staged files remain; SALU applies them on the next
    // normal close — the close hook spawns the same swap script with
    // relaunch off. The dispose flag only aborts downloads in flight;
    // this download is long done.
    _cancelRequested = false;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: 520,
        child: Container(
          decoration: BoxDecoration(
            color: context.overlayTint(context.palette.background),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.surfaceOutline),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 48,
                offset: Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(),
              Divider(height: 1, thickness: 1, color: context.palette.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: _buildBody(),
              ),
              Divider(height: 1, thickness: 1, color: context.palette.divider),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: <Widget>[
          IconTheme(
            data: IconThemeData(color: context.palette.textPrimary),
            child: DownloadMark(size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            'SALU Updater',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          SaluIconButton(
            size: 28,
            onTap: _close,
            tooltip: 'Close',
            child: const CloseMark(size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _UpdateStage.checking:
        return const _CenteredLine(
          busy: true,
          title: 'Checking for updates...',
          detail: 'Connecting to NuGet and GitHub release feeds...',
        );
      case _UpdateStage.updatesFound:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _TitleLine('New updates are available:'),
            const SizedBox(height: 12),
            _ComponentTable(result: _result!),
          ],
        );
      case _UpdateStage.upToDate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _TitleLine('✓ All components are up to date!'),
            const SizedBox(height: 12),
            _ComponentTable(result: _result!),
            const SizedBox(height: 12),
            _LastCheckedLine(checkedAt: _result!.checkedAt),
          ],
        );
      case _UpdateStage.downloading:
        return _buildDownloadingBody();
      case _UpdateStage.readyToRestart:
        // updater.md §10: a dev build gets the truth instead of a promise
        // SALU cannot keep there — reopening itself would drop out of the
        // debugger, and the next build copies the pinned files back anyway.
        final bool dev = _updater.isDevBuild;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _TitleLine('✓ Downloads Complete!'),
            const SizedBox(height: 10),
            const _DetailLine(
              'All updates are staged and ready to be applied.',
            ),
            const SizedBox(height: 4),
            _DetailLine(
              dev
                  ? 'SALU will close, install the new files, and stay closed - '
                      'start it again from VS Code. A rebuild replaces these '
                      'files with the ones the build pins, so this only affects '
                      'the build you are running.'
                  : 'SALU will close, install the new files, and reopen by '
                      'itself in a moment.',
            ),
            const SizedBox(height: 6),
            _DetailLine(
              'Staged in ${_updater.stagingDirOf()} · swap log: '
              '${_updater.swapLogPath}',
              quieter: true,
            ),
          ],
        );
      case _UpdateStage.failed:
        final String message = switch (_failureKind) {
          _UpdateFailureKind.check =>
            'Unable to connect to update servers. Check your internet connection.',
          _UpdateFailureKind.download =>
            'Could not finish downloading the update. The update server may '
                'be unavailable. Your current files were not changed.',
          _UpdateFailureKind.preparation =>
            'The update could not be prepared or verified. '
                'Your current files were not changed.',
          _UpdateFailureKind.installation =>
            'Could not start the updater. Your current files were not changed.',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DetailLine(message),
            if (_failureDetail != null) ...<Widget>[
              const SizedBox(height: 6),
              _DetailLine(_failureDetail!, quieter: true),
            ],
          ],
        );
    }
  }

  Widget _buildDownloadingBody() {
    final UpdateProgress? progress = _lastProgress;
    final int received = progress?.received ?? 0;
    final int? total = progress?.total;
    final double fraction = (total != null && total > 0)
        ? (received / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final int completed = progress?.completed ?? 0;
    final int overall =
        progress?.overall ?? _result?.pendingUpdates.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _TitleLine('Downloading components...'),
        const SizedBox(height: 12),
        _DetailLine(
          'Fetching: ${progress?.component.fileName ?? ''} '
          '(${formatUpdateBytes(received)}'
          '${total != null ? ' / ${formatUpdateBytes(total)}' : ''})',
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _UpdateProgressBar(fraction: fraction)),
            const SizedBox(width: 12),
            SizedBox(
              width: 40,
              child: Text(
                total != null && total > 0
                    ? '${(fraction * 100).round()}%'
                    : '…',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.palette.textSecondary,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailLine('Overall: $completed of $overall downloaded'),
      ],
    );
  }

  Widget _buildActions() {
    switch (_stage) {
      case _UpdateStage.checking:
        return _ActionRow(
          children: <Widget>[_UpdateAction(label: 'Cancel', onTap: _close)],
        );
      case _UpdateStage.updatesFound:
        return _ActionRow(
          children: <Widget>[
            _UpdateAction(label: 'Cancel', onTap: _close),
            const SizedBox(width: 8),
            _UpdateAction(
              label: 'Update',
              primary: true,
              onTap: _startDownload,
            ),
          ],
        );
      case _UpdateStage.upToDate:
        return _ActionRow(
          children: <Widget>[
            _UpdateAction(label: 'Close', primary: true, onTap: _close),
          ],
        );
      case _UpdateStage.downloading:
        return _ActionRow(
          children: <Widget>[_UpdateAction(label: 'Cancel', onTap: _close)],
        );
      case _UpdateStage.readyToRestart:
        // Same handoff, different promise: a dev build is not reopened.
        final bool dev = _updater.isDevBuild;
        return _ActionRow(
          children: <Widget>[
            _UpdateAction(label: 'Restart Later', onTap: _restartLater),
            const SizedBox(width: 8),
            _UpdateAction(
              label: dev ? 'Apply & Close' : 'Restart Now',
              primary: true,
              onTap: _restartNow,
            ),
          ],
        );
      case _UpdateStage.failed:
        return _ActionRow(
          children: <Widget>[
            _UpdateAction(label: 'Close', primary: true, onTap: _close),
          ],
        );
    }
  }
}

/// The component table of updater.md §8 — one row per component:
/// name · installed · (→ when updating) · latest [(Current)].
class _ComponentTable extends StatelessWidget {
  const _ComponentTable({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.overlayTint(context.palette.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.surfaceOutline),
      ),
      child: Column(
        children: <Widget>[
          const _ComponentRow(
            label: 'Component',
            installed: 'Installed',
            latest: 'Latest on Web',
            header: true,
          ),
          const SizedBox(height: 6),
          Divider(height: 1, thickness: 1, color: context.palette.divider),
          const SizedBox(height: 6),
          for (final ComponentStatus status in result.components)
            _ComponentRow(
              label: status.component.label,
              installed: status.installed ?? '—',
              latest: status.latest,
              updating: status.updateAvailable,
            ),
        ],
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.label,
    required this.installed,
    required this.latest,
    this.updating = false,
    this.header = false,
  });

  final String label;
  final String installed;
  final String latest;
  final bool updating;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: 12.5,
      fontWeight: header ? FontWeight.w600 : FontWeight.w400,
      color:
          header ? context.palette.textSecondary : context.palette.textPrimary,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(width: 118, child: Text(label, style: style)),
          const SizedBox(width: 8),
          Expanded(child: Text(installed, style: style)),
          SizedBox(
            width: 22,
            child: updating
                ? Text(
                    '→',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.palette.accent,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Text(
              latest,
              style: updating
                  ? style.copyWith(
                      color: context.palette.accent,
                      fontWeight: FontWeight.w600,
                    )
                  : style,
            ),
          ),
          if (!updating && !header)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: _CurrentTag(),
            ),
        ],
      ),
    );
  }
}

/// "(Current)" — the row that has no arrow (updater.md §8's table).
class _CurrentTag extends StatelessWidget {
  const _CurrentTag();

  @override
  Widget build(BuildContext context) {
    return Text(
      '(Current)',
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.2,
        color: context.palette.textSecondary.withAlpha(170),
      ),
    );
  }
}

/// The live progress bar (updater.md §8 · State 2C) — the family's flat
/// bar language: track + translucent fill, no thumb, no glow.
class _UpdateProgressBar extends StatelessWidget {
  const _UpdateProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Container(
          height: 6,
          decoration: BoxDecoration(
            color: context.palette.barTrack,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: (constraints.maxWidth * fraction)
                .clamp(0.0, constraints.maxWidth)
                .toDouble(),
            height: 6,
            decoration: BoxDecoration(
              color: context.palette.barFill,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      },
    );
  }
}

/// "Checking for updates…" — the busy card (same card family as the
/// firewall dialog's centered lines).
class _CenteredLine extends StatelessWidget {
  const _CenteredLine({
    required this.busy,
    required this.title,
    required this.detail,
  });

  final bool busy;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: context.overlayTint(context.palette.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.surfaceOutline),
      ),
      child: Row(
        children: <Widget>[
          if (busy) ...<Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleLine extends StatelessWidget {
  const _TitleLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: context.palette.textPrimary,
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.text, {this.quieter = false});

  final String text;
  final bool quieter;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.4,
        color: quieter
            ? context.palette.textSecondary.withAlpha(150)
            : context.palette.textSecondary,
      ),
    );
  }
}

/// "Last checked: …" — under the up-to-date table (updater.md §8, State
/// 2B), from the very round this dialog just ran.
class _LastCheckedLine extends StatelessWidget {
  const _LastCheckedLine({required this.checkedAt});

  final DateTime checkedAt;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SettingsService.instance.lastUpdateCheckTime,
      builder: (BuildContext context, int stamp, Widget? _) {
        final DateTime last =
            stamp > 0 ? DateTime.fromMillisecondsSinceEpoch(stamp) : checkedAt;
        return _DetailLine(
          'Last checked: ${formatLastChecked(DateTime.now(), last)}',
        );
      },
    );
  }
}

/// The action row's buttons — the family's outlined pill
/// (`remote_firewall_dialog.dart`'s `_DialogAction` recipe): quiet
/// outline, lights on hover, never a filled block.
class _UpdateAction extends StatefulWidget {
  const _UpdateAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_UpdateAction> createState() => _UpdateActionState();
}

class _UpdateActionState extends State<_UpdateAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool lit = _hovered;
    final Color rest = widget.primary
        ? context.palette.textPrimary
        : context.palette.textSecondary;
    final Color ink = lit ? context.palette.textPrimary : rest;
    final Color outline = (widget.primary || lit)
        ? context.palette.divider
        : context.palette.surfaceOutline;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 32,
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color:
                  lit ? context.palette.surfaceHighlight : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: outline),
            ),
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: ink,
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom button row: right-aligned like the firewall dialog's.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: children),
    );
  }
}
