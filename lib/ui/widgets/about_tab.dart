part of 'settings_dialog.dart';

// ── About tab (phase_9_details.md · step 2 — owner, 2026-09-28) ───────────
//
// A reference page, like Shortcuts: nothing here is a setting, so no group
// carries a reset mark and the master reset never reaches it. The house
// vocabulary holds — a name and a value per line (follow.md rule 1) — with
// the value allowed to be one quiet gist instead of a word. The engine
// facts are live; everything else is simply the truth about the app.

/// The app's own version. `pubspec.yaml` is `0.1.0+1` and the remote
/// protocol reports `0.1.0` — this is the one string all three agree on.
final String _kAppVersion = '0.1.0';

/// The repository, opened in SALU's own browser — never an external one
/// (the same door the remote's open-url command uses).
final String _kRepoUrl = 'https://github.com/hamamun/Salu';

/// Settings → About — who SALU is, what only it does, and the engine it
/// runs on. Pure reference: the one door on the page is the repository
/// link, and the one thing below the scroll is the owner's signature.
class _AboutTab extends StatefulWidget {
  const _AboutTab();

  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  /// mpv's own version, read once when the tab opens. `unknown` until the
  /// engine answers — a page of facts never blocks on the engine.
  String _engineVersion = 'unknown';

  @override
  void initState() {
    super.initState();
    _readEngineVersion();
  }

  Future<void> _readEngineVersion() async {
    final String raw = await PlayerService.instance.readEngineVersion();
    // The row is already named mpv — `mpv 0.38.0` reads as `0.38.0`.
    final String shown = raw.startsWith('mpv ') ? raw.substring(4) : raw;
    if (!mounted) return;
    setState(() => _engineVersion = shown.isEmpty ? 'unknown' : shown);
  }

  void _openRepo() {
    unawaited(BrowserService.instance.openInBrowser(_kRepoUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _TabBody(
            children: <Widget>[
              const _AboutHeader(),
              _groupGap,
              const _Group(
                caption: 'The player',
                rows: <Widget>[
                  _AboutLine(
                    name: 'One window',
                    gist:
                        'video, audio, subtitles, streams and the web, edge to edge — chrome only when you move.',
                  ),
                  _AboutLine(
                    name: 'One instance',
                    gist:
                        'a file opened anywhere plays in the window already open.',
                  ),
                  _AboutLine(
                    name: 'mpv underneath',
                    gist: 'hardware decoding on by default.',
                  ),
                ],
              ),
              _groupGap,
              const _Group(
                caption: 'What only SALU does',
                rows: <Widget>[
                  _AboutLine(
                    name: 'Stop parks the queue',
                    gist:
                        'Play resumes at the exact second. Stop is not Start Over.',
                  ),
                  _AboutLine(
                    name: 'The mini bar',
                    gist: 'the whole player as a 32 px always-on-top strip.',
                  ),
                  _AboutLine(
                    name: 'The EQ follows the file',
                    gist:
                        'thirteen presets for audio, four for video, chosen as it loads.',
                  ),
                  _AboutLine(
                    name: 'Your phone is the remote',
                    gist:
                        'a LAN server, paired once by QR, no cloud, no account.',
                  ),
                  _AboutLine(
                    name: 'Subtitles and lyrics',
                    gist: 'search, download, per-file sync, synced scrolling.',
                  ),
                  _AboutLine(
                    name: 'Resume memory',
                    gist: 'every file remembers where you stopped.',
                  ),
                  _AboutLine(
                    name: 'A quiet keyboard',
                    gist: 'every key works, none is printed in the interface.',
                  ),
                  _AboutLine(
                    name: 'The Living Map',
                    gist:
                        'Settings → Shortcuts is SALU itself, shrunken and answering.',
                  ),
                ],
              ),
              _groupGap,
              const _Group(
                caption: 'Channels',
                rows: <Widget>[
                  _AboutLine(
                    name: 'm3u lists, URL or file',
                    gist:
                        "SALU's own incremental parser reads them entry by entry as they arrive, off the UI thread. Fifty thousand channels, no cap.",
                  ),
                  _AboutLine(
                    name: 'Group by Flat · Category · Language · Country',
                    gist:
                        'ISO aliases share a group, and language and country are read out of the entry itself when the file leaves them out.',
                  ),
                  _AboutLine(
                    name: 'Favourites per provider',
                    gist:
                        'they survive a credential rotation, and never store a URL.',
                  ),
                  _AboutLine(
                    name: 'Live, on an inert timeline',
                    gist:
                        'a still soft light while data arrives; search matches name and group, never the URL.',
                  ),
                ],
              ),
              _groupGap,
              const _Group(
                caption: 'The browser',
                rows: <Widget>[
                  _AboutLine(
                    name: 'Tabs, bookmarks, downloads',
                    gist:
                        'beside the video; a held-back pop-up never escapes to a window of its own.',
                  ),
                  _AboutLine(
                    name: "Windows' own Edge engine",
                    gist:
                        'WebView2, the runtime Windows already ships. No custom engine, nothing extra installed.',
                  ),
                ],
              ),
              _groupGap,
              _Group(
                caption: 'Engine',
                rows: <Widget>[
                  _Row(label: 'mpv', value: _engineVersion),
                  const _DecoderRow(),
                  const _Row(label: 'Platform', value: 'Windows 10/11'),
                  const _Row(label: 'Storage', value: 'shared_preferences'),
                ],
              ),
              _groupGap,
              _Group(
                caption: 'Credits',
                rows: <Widget>[
                  _Row(
                    label: 'Source',
                    value: 'github.com/hamamun/Salu',
                    valueTooltip: _kRepoUrl,
                    onTap: _openRepo,
                    trailing: SaluIconButton(
                      onTap: _openRepo,
                      tooltip: 'Open repository',
                      size: 26,
                      child: const LinkMark(size: 16),
                    ),
                  ),
                  const _Row(
                    label: 'Built with',
                    value: 'mpv · media_kit · Flutter · WebView2',
                  ),
                ],
              ),
            ],
          ),
        ),
        const _AboutSignature(),
      ],
    );
  }
}

/// The identity block — the app tile, the name, the version, one line. The
/// only centered thing on the page; the list below is the house
/// left-aligned column as everywhere else.
class _AboutHeader extends StatelessWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/images/salu_logo.png',
            width: 44,
            height: 44,
            filterQuality: FilterQuality.medium,
            // A caption-size decode of the app icon: sharp at any DPI, and
            // nowhere near the cost of the full-size PNG.
            cacheWidth: 96,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) {
              // Never a broken-image glyph — a thin frame in the family's
              // ink, the same fallback the mini bar's tile wears.
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.palette.surfaceOutline),
                ),
                child: const SizedBox(width: 44, height: 44),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'SALU',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text('Version $_kAppVersion', style: _valueStyle(context)),
        const SizedBox(height: 5),
        Text(
          'A borderless media player for Windows.',
          style: _defaultCaptionStyle(context),
        ),
      ],
    );
  }
}

/// One feature as a name and a gist — the house list's own shape with the
/// value allowed to run past one word. The name is primary ink, the gist
/// quiet. Nothing on the line is interactive, so nothing on it lights: a
/// reference page never implies a control it does not have.
class _AboutLine extends StatelessWidget {
  const _AboutLine({required this.name, required this.gist});

  final String name;
  final String gist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: name,
              style: _labelStyle(context).copyWith(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' — ', style: _valueStyle(context)),
            TextSpan(text: gist, style: _valueStyle(context)),
          ],
        ),
      ),
    );
  }
}

/// The decoder actually in use right now — the same notifier the Info
/// panel reads, so the two can never disagree. `—` until something has
/// played and mpv has answered.
class _DecoderRow extends StatelessWidget {
  const _DecoderRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: PlayerService.instance.activeHwdec,
      builder: (BuildContext context, String? hwdec, Widget? _) =>
          _Row(label: 'Decoder', value: hwdec ?? '—'),
    );
  }
}

/// The owner's signature — pinned under the scroll, so it always sits at
/// the tab's bottom edge however far the page is scrolled, and painted in
/// [AppColors.whisper] so it is there if you look for it and gone if you
/// don't. Never a control, never framed.
class _AboutSignature extends StatelessWidget {
  const _AboutSignature();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        'created by HAM',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.8,
          color: context.palette.whisper,
        ),
      ),
    );
  }
}
