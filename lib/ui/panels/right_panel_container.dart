import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'tabs/audio_tab.dart';
import 'tabs/playlist_tab.dart';
import 'tabs/subtitle_tab.dart';
import 'tabs/video_tab.dart';

/// The slide-out "Quick Settings" panel (Phase 4 · Step 1).
///
/// Slides in from the right edge with a blurred-glass background, hosting
/// four tabs: Playlist, Video, Audio, Subtitles.
class RightPanel extends StatelessWidget {
  const RightPanel({
    super.key,
    required this.visible,
    required this.onClose,
    required this.onOpenSettings,
  });

  final bool visible;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(1, 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !visible,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 340,
              height: double.infinity,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.divider)),
              ),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    color: AppColors.glass,
                    // A Material directly above the glass tint gives the
                    // ListTiles / SwitchListTiles in the tabs a surface to
                    // paint their ink on. Without it the splash renders on
                    // a Material behind this opaque Container and Flutter
                    // warns that it "may be invisible".
                    child: Material(
                      type: MaterialType.transparency,
                      child: DefaultTabController(
                        length: 4,
                        child: Column(
                          children: <Widget>[
                            _PanelHeader(
                              onOpenSettings: onOpenSettings,
                              onClose: onClose,
                            ),
                            const TabBar(
                              labelColor: AppColors.accent,
                              unselectedLabelColor: AppColors.textSecondary,
                              indicatorColor: AppColors.accent,
                              indicatorWeight: 2,
                              labelStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              tabs: <Tab>[
                                Tab(text: 'Playlist'),
                                Tab(text: 'Video'),
                                Tab(text: 'Audio'),
                                Tab(text: 'Subtitles'),
                              ],
                            ),
                            const Expanded(
                              child: TabBarView(
                                children: <Widget>[
                                  PlaylistTab(),
                                  VideoTab(),
                                  AudioTab(),
                                  SubtitleTab(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onOpenSettings, required this.onClose});

  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            const Text(
              'SALU',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined,
                  size: 20, color: AppColors.textPrimary),
              onPressed: onOpenSettings,
            ),
            IconButton(
              tooltip: 'Close panel',
              icon: const Icon(Icons.close_rounded,
                  size: 20, color: AppColors.textPrimary),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
