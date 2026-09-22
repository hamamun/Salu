import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/remote/remote_firewall.dart';
import '../../core/remote/remote_service.dart';
import '../../core/settings_service.dart';
import '../../core/ui_lock.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'salu_marks.dart';
import 'web_marks.dart';

/// The tier-2 firewall ask (remote.md §8.3, amended 2026-09-21): SALU's own
/// dialog, shown the moment Remote is switched on — which is the only moment
/// the question can honestly be asked, because a blocked phone-call never
/// reaches the PC at all. One [Allow] → one Windows UAC → the inbound rule
/// is written, scoped to this exe + the remote port window + Private
/// networks → verified aloud.
///
/// The dialog is also the fix door for the two traps the panel reports: the
/// Windows-Security Cancel trap (a permanent Block rule) and the stale rule
/// of a moved portable build. Whatever Windows refuses (group policy,
/// antivirus firewalls) degrades in copy to the manual fallback — the same
/// `control firewall.cpl` door the 90-second hint has always offered.
Future<void> showRemoteFirewallDialog(BuildContext context) {
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
        const _RemoteFirewallDialog(),
  ).whenComplete(ChromeLock.instance.release);
}

bool _firewallDialogShowing = false;

/// The Remote-ON trigger: check, and only speak when there is something to
/// fix. Quiet on healthy machines, quiet off Windows, quiet on probes that
/// fail (those stay the 90-second hint's job).
Future<void> maybePromptRemoteFirewall(BuildContext context) async {
  final RemoteFirewallStatus status =
      await RemoteFirewallService.instance.recheck();
  if (!status.needsAttention || _firewallDialogShowing) return;
  if (!context.mounted) return;
  _firewallDialogShowing = true;
  try {
    await showRemoteFirewallDialog(context);
  } finally {
    _firewallDialogShowing = false;
  }
}

enum _Stage { reading, review, applying, done, declined, failed }

class _RemoteFirewallDialog extends StatefulWidget {
  const _RemoteFirewallDialog();

  @override
  State<_RemoteFirewallDialog> createState() => _RemoteFirewallDialogState();
}

class _RemoteFirewallDialogState extends State<_RemoteFirewallDialog> {
  _Stage _stage = _Stage.reading;
  bool _makePrivate = true;
  bool _askedPrivate = false;
  String? _failureDetail;
  bool _alreadyHealthy = false;

  RemoteFirewallService get _firewall => RemoteFirewallService.instance;

  @override
  void initState() {
    super.initState();
    // Always ask Windows fresh: the panel's status may predate the user
    // answering Windows' own popup, and the fix must never be offered for a
    // rule that already exists.
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final RemoteFirewallStatus fresh = await _firewall.recheck(force: true);
    if (!mounted) return;
    setState(() {
      // "Already allowed" is only ever claimed on a confirmed ok — a probe
      // that failed (unknown) gets the manual fallback copy, never a green.
      _alreadyHealthy = fresh.ruleState == RemoteFirewallRuleState.ok &&
          !fresh.needsAttention;
      _makePrivate = fresh.needsPrivateNetwork;
      _stage = _Stage.review;
    });
  }

  Future<void> _applyFix() async {
    // The UAC round-trip is one at a time; a mashed Allow must not start a
    // second elevation (its early "cancelled" would hide the real result).
    if (_firewall.applying.value) return;
    final RemoteFirewallStatus status = _firewall.status.value;
    final bool flipNetworks = status.needsPrivateNetwork && _makePrivate;
    setState(() {
      _stage = _Stage.applying;
      _askedPrivate = flipNetworks;
    });
    final RemoteFirewallFixResult result =
        await _firewall.fix(makePrivate: flipNetworks);
    if (!mounted) return;
    setState(() {
      switch (result.outcome) {
        case RemoteFirewallFixOutcome.applied:
          _stage = _Stage.done;
        case RemoteFirewallFixOutcome.cancelled:
          _stage = _Stage.declined;
        case RemoteFirewallFixOutcome.failed:
          _failureDetail = result.detail;
          _stage = _Stage.failed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: 440,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceOutline),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 48,
                offset: Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              _firewall.status,
              _firewall.applying,
            ]),
            builder: (BuildContext context, Widget? _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildHeader(),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: _buildBody(),
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                  _buildActions(),
                ],
              );
            },
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
          const IconTheme(
            data: IconThemeData(color: AppColors.textPrimary),
            child: ShieldMark(size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            'Windows Firewall',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          SaluIconButton(
            size: 28,
            onTap: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            child: const CloseMark(size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.reading:
        return const _CenteredLine(
          busy: true,
          text: 'Asking Windows about SALU’s firewall rule…',
        );
      case _Stage.applying:
        return const _CenteredLine(
          busy: true,
          text: 'Waiting for Windows — say “Yes” on the prompt that follows.',
        );
      case _Stage.done:
        return _doneBody();
      case _Stage.declined:
        return const _MessageBody(
          title: 'Nothing changed.',
          text: 'The Windows prompt was declined, so the firewall stays as it '
              'is. Phones still can’t reach SALU until it lets SALU through.',
        );
      case _Stage.failed:
        return _failedBody();
      case _Stage.review:
        return _reviewBody();
    }
  }

  Widget _reviewBody() {
    if (_alreadyHealthy) {
      return const _MessageBody(
        title: 'SALU is already allowed.',
        text: 'Windows has a working firewall rule for this SALU — nothing '
            'to do here.',
      );
    }
    final RemoteFirewallStatus status = _firewall.status.value;
    final int preferredPort = SettingsService.instance.remotePort.value;
    final String headline;
    final String explanation;
    switch (status.ruleState) {
      case RemoteFirewallRuleState.blocked:
        headline = 'Windows is blocking SALU.';
        explanation = 'An earlier “Cancel” on Windows’ security prompt wrote '
            'a permanent block rule, and block rules win over everything. '
            'The fix removes the block and adds a proper allow in its place.';
      case RemoteFirewallRuleState.stalePath:
        headline = 'SALU’s firewall rule points at an old location.';
        explanation = 'The app moved (or a new build replaced it) after the '
            'rule was written — Windows keeps honoring the dead path. '
            'Re-adding the rule for this SALU takes one prompt.';
      case RemoteFirewallRuleState.missing:
        headline = 'Phones on your Wi-Fi need permission to reach SALU.';
        explanation = 'Windows Firewall guards new apps by default. Allowing '
            'adds one inbound rule — this app, TCP port $preferredPort and '
            'its retry neighbours, private networks only.';
      case RemoteFirewallRuleState.ok:
        headline = 'This Wi-Fi is marked as a Public network.';
        explanation = 'The firewall rule is fine, but Windows hides PCs from '
            'other devices on Public networks, so phones still won’t find '
            'SALU. A home Wi-Fi belongs to Private.';
      case RemoteFirewallRuleState.unknown:
        headline = 'Windows Firewall may be blocking SALU.';
        explanation = 'SALU couldn’t read the firewall state — a security '
            'suite may own it. If phones can’t connect, allow SALU by hand.';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MessageBody(title: headline, text: explanation),
        if (status.needsRuleFix && status.needsPrivateNetwork) ...<Widget>[
          const SizedBox(height: 12),
          _PrivateNetworkRow(
            aliases: status.publicAliases,
            value: _makePrivate,
            onChanged: (bool v) => setState(() => _makePrivate = v),
          ),
        ],
      ],
    );
  }

  Widget _doneBody() {
    final RemoteService remote = RemoteService.instance;
    final String? address = remote.address.value;
    final int? port = remote.port.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: IconTheme(
                data: IconThemeData(color: AppColors.statusAlive),
                child: TickMark(size: 15),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _madePrivateApplied
                    ? 'Done — phones on your Wi-Fi can reach SALU, and '
                        'the network is now Private.'
                    : 'Done — phones on your Wi-Fi can now reach SALU.',
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (address != null && port != null) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceOutline),
            ),
            child: Text(
              'Available on ${remote.networkName.value ?? 'LAN'} · $address · $port',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The done line only claims the Private flip when this run asked for it
  /// and Windows confirms no Public profile remains — "done" must never
  /// promise what wasn't run.
  bool get _madePrivateApplied =>
      _askedPrivate && _firewall.status.value.publicAliases.isEmpty;

  Widget _failedBody() {
    final String? detail = _failureDetail;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MessageBody(
          title: 'Windows didn’t apply the change.',
          text: 'A company policy or an antivirus firewall may own this '
              'machine. Allow SALU by hand in the firewall settings — one '
              'inbound rule, TCP port '
              '${SettingsService.instance.remotePort.value}, private networks.',
        ),
        if (detail != null && detail.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceOutline),
            ),
            child: Text(
              detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    final RemoteFirewallStatus status = _firewall.status.value;
    switch (_stage) {
      case _Stage.reading:
      case _Stage.applying:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _DialogAction(
                label: 'Not now',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      case _Stage.done:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _DialogAction(
                label: 'Done',
                primary: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      case _Stage.declined:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _DialogAction(
                label: 'Not now',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              _DialogAction(
                label: 'Try again',
                primary: true,
                onTap: _applyFix,
              ),
            ],
          ),
        );
      case _Stage.failed:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _DialogAction(
                label: 'Open firewall settings',
                onTap: _firewall.openWindowsFirewallSettings,
              ),
              const SizedBox(width: 8),
              _DialogAction(
                label: 'Try again',
                primary: true,
                onTap: _applyFix,
              ),
            ],
          ),
        );
      case _Stage.review:
        if (_alreadyHealthy) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _DialogAction(
                  label: 'Done',
                  primary: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
        if (status.ruleState == RemoteFirewallRuleState.unknown) {
          // Nothing to offer programmatically — the manual door is the
          // whole body here, just like the 90-second hint.
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _DialogAction(
                  label: 'Not now',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _DialogAction(
                  label: 'Open firewall settings',
                  primary: true,
                  onTap: _firewall.openWindowsFirewallSettings,
                ),
              ],
            ),
          );
        }
        final bool flipNetworks = status.needsPrivateNetwork && _makePrivate;
        final String primaryLabel = !status.needsRuleFix
            ? 'Set Wi-Fi to Private'
            : flipNetworks
                ? 'Allow SALU & set private'
                : 'Allow SALU in firewall';
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _firewall.openWindowsFirewallSettings,
                  child: const Text(
                    'Do it by hand instead',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              _DialogAction(
                label: 'Not now',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              _DialogAction(
                label: primaryLabel,
                primary: true,
                onTap: _applyFix,
              ),
            ],
          ),
        );
    }
  }
}

/// The state card — headline + one honest explanation, the same voice as the
/// Clear browsing data dialog's protection card.
class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Public-network consent row: SALU never flips a network profile
/// silently — the checkbox is the ask, on by default for a home-looking
/// Wi-Fi because a Private firewall rule can never work while it stays
/// Public.
class _PrivateNetworkRow extends StatefulWidget {
  const _PrivateNetworkRow({
    required this.aliases,
    required this.value,
    required this.onChanged,
  });

  final List<String> aliases;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_PrivateNetworkRow> createState() => _PrivateNetworkRowState();
}

class _PrivateNetworkRowState extends State<_PrivateNetworkRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final String names = widget.aliases.isEmpty
        ? 'this network'
        : widget.aliases.map((String a) => '“$a”').join(', ');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color:
                _hovered ? AppColors.surfaceHighlight : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _SaluCheckbox(checked: widget.value),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Mark $names as a private network',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Recommended for home Wi-Fi — Public hides the PC from phones.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaluCheckbox extends StatelessWidget {
  const _SaluCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? AppColors.iconIdle : AppColors.statusUnknown,
          width: 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: checked
          ? const IconTheme(
              data: IconThemeData(color: AppColors.textPrimary),
              child: TickMark(size: 12),
            )
          : null,
    );
  }
}

class _CenteredLine extends StatelessWidget {
  const _CenteredLine({required this.busy, required this.text});

  final bool busy;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Row(
        children: <Widget>[
          if (busy) ...<Widget>[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dialog's labelled action — the family's one outlined pill (same
/// recipe as the Clear browsing data dialog): quiet outline, lights on
/// hover, never a filled block. [onTap] null disables.
class _DialogAction extends StatefulWidget {
  const _DialogAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_DialogAction> createState() => _DialogActionState();
}

class _DialogActionState extends State<_DialogAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool on = widget.onTap != null;
    final bool lit = on && _hovered;
    final Color rest =
        widget.primary ? AppColors.textPrimary : AppColors.textSecondary;
    final Color ink = !on
        ? AppColors.textSecondary.withAlpha(110)
        : (lit ? Colors.white : rest);
    final Color outline = !on
        ? AppColors.surfaceOutline.withAlpha(140)
        : (widget.primary || lit
            ? AppColors.divider
            : AppColors.surfaceOutline);

    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _pressed = true) : null,
        onTapUp: on ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: on ? () => setState(() => _pressed = false) : null,
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
              color: lit ? AppColors.surfaceHighlight : Colors.transparent,
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
