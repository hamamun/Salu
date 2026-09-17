import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../core/web/web_address.dart';
import '../../core/web/web_tab.dart';
import '../../theme/app_theme.dart';
import 'salu_icon_button.dart';
import 'web_marks.dart';

/// SALU's start page — plain Flutter, no HTML, no engine (web.md · "the
/// start page is plain Flutter: the SALU logo and the words SALU Web
/// Browser"). It is what the last closed tab leaves behind, what a fresh
/// tab greets you with, and what Home keeps visible when there is no loaded
/// website: nothing is initialized until the address bar sends a page off.
class WebStartPage extends StatelessWidget {
  const WebStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/salu_logo.png',
              width: 96,
              height: 96,
              errorBuilder: (BuildContext c, Object e, StackTrace? st) {
                return Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  child: const Icon(Icons.public,
                      size: 48, color: AppColors.textSecondary),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'SALU Web Browser',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab's content: lazy until activated, an engine while started, an
/// error card when a load dies (Reload is the only word it speaks).
class WebTabView extends StatelessWidget {
  const WebTabView({super.key, required this.tab});

  final WebTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.controller == null) {
      return ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[tab.loading, tab.failed]),
        builder: (BuildContext context, Widget? _) {
          if (tab.failed.value) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'This page didn’t load',
                    style: TextStyle(
                        fontSize: 13.5, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 14),
                  SaluIconButton(
                    size: 34,
                    onTap: tab.reload,
                    tooltip: 'Reload',
                    child: const ReloadMark(size: 26),
                  ),
                ],
              ),
            );
          }
          if (tab.loading.value) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textPrimary,
                ),
              ),
            );
          }
          return const WebStartPage();
        },
      );
    }
    return _WebviewHost(controller: tab.controller!, tab: tab);
  }
}

class _WebviewHost extends StatefulWidget {
  const _WebviewHost({required this.controller, required this.tab});

  final WebviewController controller;
  final WebTab tab;

  @override
  State<_WebviewHost> createState() => _WebviewHostState();
}

class _WebviewHostState extends State<_WebviewHost> {
  bool _asking = false;

  /// Popups arrive through the engine's permission delegate (web.md ·
  /// "pop-ups blocked + tidy permission prompts"): only a prompt the page
  /// asked FOR after a real click passes as user-initiated; anything else
  /// answers deny without ever showing a card. One prompt at a time.
  Future<WebviewPermissionDecision> _onPermissionRequested(
    String url,
    WebviewPermissionKind kind,
    bool isUserInitiated,
  ) async {
    if (!isUserInitiated) return WebviewPermissionDecision.deny;
    if (_asking || !mounted) return WebviewPermissionDecision.deny;
    _asking = true;
    WebviewPermissionDecision decision = WebviewPermissionDecision.deny;
    try {
      final WebviewPermissionDecision? picked =
          await showDialog<WebviewPermissionDecision>(
        context: context,
        barrierColor: const Color(0x99000000),
        builder: (BuildContext context) =>
            _PermissionPrompt(url: url, kind: kind),
      );
      if (picked != null) decision = picked;
    } finally {
      _asking = false;
    }
    return decision;
  }

  @override
  Widget build(BuildContext context) {
    return Webview(
      widget.controller,
      permissionRequested: _onPermissionRequested,
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.url, required this.kind});

  final String url;
  final WebviewPermissionKind kind;

  static String _phrase(WebviewPermissionKind k) =>
      switch (k) {
        WebviewPermissionKind.microphone => 'your microphone',
        WebviewPermissionKind.camera => 'your camera',
        WebviewPermissionKind.geoLocation => 'your location',
        WebviewPermissionKind.notifications => 'notifications',
        WebviewPermissionKind.clipboardRead => 'the clipboard',
        WebviewPermissionKind.otherSensors => 'its sensors',
        WebviewPermissionKind.unknown => 'extra access',
      };

  @override
  Widget build(BuildContext context) {
    final String host = WebAddress.hostOf(url);
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.surfaceOutline),
      ),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: host,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const TextSpan(text: ' is asking for '),
                    TextSpan(
                      text: _phrase(kind),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const TextSpan(text: '.'),
                  ],
                  style: const TextStyle(
                      fontSize: 13, height: 1.5,
                      color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(WebviewPermissionDecision.deny),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Block',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(WebviewPermissionDecision.allow),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Allow',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
