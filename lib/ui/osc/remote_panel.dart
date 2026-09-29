import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/remote/remote_firewall.dart';
import '../../core/remote/remote_pairing.dart';
import '../../core/remote/remote_service.dart';
import '../../core/settings_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/remote_firewall_dialog.dart';
import '../widgets/salu_icon_button.dart';
import '../widgets/salu_marks.dart';

/// QR pairing surface. The pairing code is owned by RemoteService and is
/// stable for the lifetime of this dialog; disposing the dialog rotates it.
///
/// **Compact pass (owner ruling, 2026-09-28).** The panel sizes itself to
/// its content — a 340 px column that grows and shrinks with the phone
/// list, so no scroll bar and no reserved empty space. It prints the
/// status, the ticket and the phone rows, and nothing else: the "Scan with
/// SALU Remote" line, the footnote about the code changing, and the empty
/// phones sentence are gone (follow.md rule 1), and every action is a mark
/// with a tooltip (rule 6).
///
/// **The QR itself is untouched** — 208 px on a white card with its 12 px
/// quiet zone, no scaling, no animation. The APK reads it perfectly and
/// nothing here moves a module.
class RemotePanel extends StatefulWidget {
  const RemotePanel({super.key});

  @override
  State<RemotePanel> createState() => _RemotePanelState();
}

class _RemotePanelState extends State<RemotePanel> {
  final RemoteService _remote = RemoteService.instance;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _remote.openPairingPanel();
    _opened = true;
  }

  @override
  void dispose() {
    if (_opened) {
      _remote.closePairingPanel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: SizedBox(
              width: 340,
              child: Container(
                decoration: BoxDecoration(
                  color: context.overlayTint(context.palette.surface),
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
                  children: <Widget>[
                    _header(),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: context.palette.divider,
                    ),
                    Flexible(
                      child: ScrollConfiguration(
                        // No bar, ever: the panel fits its content, and the
                        // scroll view is only a small-window fallback.
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: _body(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: <Widget>[
            const QrMark(size: 18),
            const SizedBox(width: 10),
            Text(
              'Remote',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            SaluIconButton(
              size: 30,
              tooltip: 'Close',
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      );

  Widget _body() => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _remote.status,
          _remote.statusDetail,
          _remote.port,
          _remote.address,
          _remote.networkName,
          _remote.pairingCode,
          _remote.devices,
          _remote.connectedCount,
          _remote.firewallTick,
          RemoteFirewallService.instance.status,
          SettingsService.instance.remoteEnabled,
          SettingsService.instance.remoteFileAccess,
        ]),
        builder: (BuildContext context, Widget? _) {
          final String? payload = _remote.qrPayload;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _statusLine(),
              const SizedBox(height: 12),
              if (payload != null) ...<Widget>[
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: payload,
                      size: 208,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // The manual-entry fallback for phones without a working
                // camera. It is a value, so it carries no sentence.
                Center(
                  child: Text(
                    formatPairingCode(_remote.pairingCode.value ?? ''),
                    style: TextStyle(
                      fontSize: 15,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
              ] else if (_remote.status.value == RemoteStatus.running)
                // Running but with no private address to pair over — the
                // one case the box speaks for. Off is already said by the
                // status line above, so nothing is repeated under it.
                _emptyNetwork(),
              ..._phones(),
              ..._firewallArea(),
            ],
          );
        },
      );

  /// One line of state: a dot and the shortest true thing about it. No
  /// sentence ever — `Off` is `Off`, and the settings door is a tooltip
  /// away on the switch that turns it on.
  Widget _statusLine() {
    final RemoteStatus state = _remote.status.value;
    final String? address = _remote.address.value;
    final String network = _remote.networkName.value ?? 'LAN';
    final String copy;
    if (state == RemoteStatus.off) {
      copy = 'Off';
    } else if (state == RemoteStatus.starting) {
      copy = 'Starting…';
    } else if (state == RemoteStatus.failed) {
      copy = _remote.statusDetail.value ?? "Couldn't start";
    } else if (address == null) {
      copy = _remote.statusDetail.value ?? 'Not on a local network';
    } else if (_remote.connectedCount.value > 0) {
      copy = 'Connected · $network · $address:${_remote.port.value}';
    } else {
      copy = 'Waiting · $network · $address:${_remote.port.value}';
    }
    final bool good = state == RemoteStatus.running && address != null;
    return Row(
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: good
                ? context.palette.statusAlive
                : context.palette.statusUnknown,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            copy,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: context.palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyNetwork() => Container(
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.overlayTint(context.palette.background),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'A private Wi-Fi or Ethernet address is needed for pairing.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12, color: context.palette.textSecondary),
          ),
        ),
      );

  /// The paired phones — the group exists only while it has a member. An
  /// empty list is not a state SALU narrates (rule 1), and with no phones
  /// there is nothing to forget.
  List<Widget> _phones() {
    final List<RemoteDevice> list = _remote.devices.value;
    if (list.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 14),
      Text(
        'PHONES',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: context.palette.textSecondary,
        ),
      ),
      const SizedBox(height: 2),
      for (final RemoteDevice device in list)
        _PhoneRow(
          name: device.name,
          state: device.control
              ? 'has control'
              : (device.online ? 'connected' : _lastSeen(device)),
          onForget: () => _remote.forgetDevice(device.id),
        ),
    ];
  }

  /// The panel's firewall surface (remote.md §8.3, amended 2026-09-21).
  ///
  /// Two tiers, one truth: when the fresh probe knows the firewall is the
  /// problem — missing rule, Cancel-trap block rule, dead rule of a moved
  /// build, Public Wi-Fi profile — the row names it and offers the one-UAC
  /// fix. When the probe can't say (third-party firewall, group policy),
  /// the original 90-second hint still lands after a connectionless wait,
  /// with the manual settings door.
  List<Widget> _firewallArea() {
    if (_remote.status.value != RemoteStatus.running) {
      return const <Widget>[];
    }
    final RemoteFirewallStatus firewall =
        RemoteFirewallService.instance.status.value;
    if (firewall.needsAttention) {
      final String copy = switch (firewall.ruleState) {
        RemoteFirewallRuleState.blocked => 'Windows Firewall is blocking SALU.',
        RemoteFirewallRuleState.missing => 'Phones need a firewall permission.',
        RemoteFirewallRuleState.stalePath =>
          'SALU moved — the firewall rule is stale.',
        _ => 'This Wi-Fi is Public.',
      };
      return <Widget>[
        const SizedBox(height: 12),
        _HintRow(
          text: copy,
          icon: Icons.build_outlined,
          tooltip: 'Fix firewall rule',
          onTap: () => unawaited(showRemoteFirewallDialog(context)),
        ),
      ];
    }
    if (_remote.firewallHintVisible) {
      return <Widget>[
        const SizedBox(height: 12),
        _HintRow(
          text: 'Windows Firewall may be blocking SALU.',
          icon: Icons.settings_outlined,
          tooltip: 'Windows Firewall settings',
          onTap: () => unawaited(
            RemoteFirewallService.instance.openWindowsFirewallSettings(),
          ),
        ),
      ];
    }
    return const <Widget>[];
  }

  String _lastSeen(RemoteDevice device) {
    final DateTime? seen = device.lastSeenAt;
    if (seen == null) return 'not connected';
    final Duration age = DateTime.now().difference(seen);
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }
}

/// One paired phone: name, state, and the forget mark.
class _PhoneRow extends StatefulWidget {
  const _PhoneRow({
    required this.name,
    required this.state,
    required this.onForget,
  });

  final String name;
  final String state;
  final VoidCallback onForget;

  @override
  State<_PhoneRow> createState() => _PhoneRowState();
}

class _PhoneRowState extends State<_PhoneRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 30,
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: _hovered
              ? context.palette.resolve(
                  const Color(0x0DFFFFFF),
                  const Color(0x0D000000),
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.state,
              style: TextStyle(
                fontSize: 12,
                color: context.palette.textSecondary,
              ),
            ),
            SaluIconButton(
              size: 24,
              tooltip: 'Forget',
              onTap: widget.onForget,
              child: const Icon(Icons.close, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one warning line the panel may show — state plus the mark that
/// fixes it. Silent the rest of the time (rule 1).
class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.text,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          Icons.warning_amber_outlined,
          size: 14,
          color: context.palette.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
            ),
          ),
        ),
        SaluIconButton(
          size: 26,
          tooltip: tooltip,
          onTap: onTap,
          child: Icon(icon, size: 14),
        ),
      ],
    );
  }
}
