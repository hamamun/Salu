import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/remote/remote_pairing.dart';
import '../../core/remote/remote_service.dart';
import '../../core/settings_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/salu_marks.dart';

/// QR pairing surface. The pairing code is owned by RemoteService and is
/// stable for the lifetime of this dialog; disposing the dialog rotates it.
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
      child: SizedBox(
        width: 400,
        height: 520,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF333336)),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x80000000), blurRadius: 48, offset: Offset(0, 16)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _header(),
              const Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: _body(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Row(
          children: <Widget>[
            const QrMark(size: 20),
            const SizedBox(width: 12),
            const Text('Remote', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Spacer(),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              onPressed: () => Navigator.of(context).pop(),
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
          SettingsService.instance.remoteEnabled,
          SettingsService.instance.remoteFileAccess,
        ]),
        builder: (BuildContext context, Widget? _) {
          final String? payload = _remote.qrPayload;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _statusLine(),
              const SizedBox(height: 14),
              if (payload != null)
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
                )
              else
                _emptyNetwork(),
              if (payload != null) ...<Widget>[
                const SizedBox(height: 10),
                Center(child: Text('Scan with SALU Remote', style: _secondaryStyle)),
                const SizedBox(height: 4),
                Center(child: Text(formatPairingCode(_remote.pairingCode.value ?? ''), style: const TextStyle(fontSize: 18, letterSpacing: 2.2, color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
                const SizedBox(height: 5),
                const Center(child: Text('This code is only for pairing. It changes when you close this panel.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary))),
              ],
              const SizedBox(height: 18),
              _phones(),
              if (_remote.firewallHintVisible) ...<Widget>[
                const SizedBox(height: 16),
                _firewallHint(),
              ],
            ],
          );
        },
      );

  Widget _statusLine() {
    final RemoteStatus state = _remote.status.value;
    final String copy;
    if (state == RemoteStatus.off) {
      copy = 'Remote is off — turn it on in Settings';
    } else if (state == RemoteStatus.starting) {
      copy = 'Starting…';
    } else if (state == RemoteStatus.failed) {
      copy = _remote.statusDetail.value ?? "Couldn't start the remote";
    } else if (_remote.connectedCount.value > 0 && _remote.address.value != null) {
      copy = 'Connected · ${_remote.networkName.value ?? 'LAN'} · ${_remote.address.value} · ${_remote.port.value}';
    } else if (_remote.address.value == null) {
      copy = _remote.statusDetail.value ?? 'SALU is not on a local network';
    } else {
      copy = 'Waiting for your phone · ${_remote.networkName.value ?? 'LAN'} · ${_remote.address.value}:${_remote.port.value}';
    }
    final bool good = state == RemoteStatus.running && _remote.address.value != null;
    return Row(
      children: <Widget>[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: good ? const Color(0xFF70C28A) : AppColors.textSecondary, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(copy, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
      ],
    );
  }

  Widget _emptyNetwork() => Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
        child: const Text('A private Wi-Fi or Ethernet address is needed for pairing.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );

  Widget _phones() {
    final List<RemoteDevice> list = _remote.devices.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Phones', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Text('No phones paired yet.', style: _secondaryStyle)
        else
          ...list.map((RemoteDevice device) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(device.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                    Text(device.control ? 'has control' : device.online ? 'connected' : _lastSeen(device), style: _secondaryStyle),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _remote.forgetDevice(device.id),
                      child: const Text('Forget', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _firewallHint() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_outlined, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Expanded(child: Text("Can't connect? Windows Firewall may be blocking SALU.", style: _secondaryStyle)),
          TextButton(onPressed: () => Process.start('control', <String>['firewall.cpl'], mode: ProcessStartMode.detached), child: const Text('Open firewall settings', style: TextStyle(fontSize: 11))),
        ],
      );

  String _lastSeen(RemoteDevice device) {
    final DateTime? seen = device.lastSeenAt;
    if (seen == null) return 'not connected';
    final Duration age = DateTime.now().difference(seen);
    if (age.inMinutes < 1) return 'last seen just now';
    if (age.inHours < 1) return 'last seen ${age.inMinutes}m ago';
    return 'last seen ${age.inHours}h ago';
  }

  static const TextStyle _secondaryStyle = TextStyle(fontSize: 12, color: AppColors.textSecondary);
}
