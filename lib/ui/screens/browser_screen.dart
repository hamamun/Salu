import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../core/stream_manager.dart';
import '../../theme/app_theme.dart';
import '../widgets/osd_indicator.dart';

/// One open browser tab, owning its own WebView2 controller.
class BrowserTab {
  BrowserTab({required this.homeUrl, required String title})
      : title = ValueNotifier<String>(title),
        currentUrl = ValueNotifier<String>(homeUrl);

  final String homeUrl;
  final ValueNotifier<String> title;
  final ValueNotifier<String> currentUrl;
  final WebviewController controller = WebviewController();

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _disposed = false;
  Future<void>? _initFuture;

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// Safe to call repeatedly / concurrently — the work happens once.
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    if (_initialized || _disposed) return;
    try {
      await controller.initialize();
      controller.url.listen((String url) {
        if (!_disposed) currentUrl.value = url;
      });
      controller.title.listen((String value) {
        if (!_disposed && value.trim().isNotEmpty) title.value = value.trim();
      });
      await controller.setBackgroundColor(AppColors.background);
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      _initialized = true;
      await controller.loadUrl(homeUrl);
    } catch (err) {
      if (!_disposed) {
        error.value =
            'WebView2 runtime unavailable.\n'
            'Install the Microsoft Edge WebView2 Runtime, then reopen the browser.';
      }
      debugPrint('[SALU] webview init failed: $err');
    }
  }

  /// Phase 6 · Memory management: destroy the controller and flush its cache.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (_initialized) {
        await controller.clearCache();
        await controller.clearCookies();
      }
      await controller.dispose();
    } catch (err) {
      debugPrint('[SALU] webview dispose failed: $err');
    }
    title.dispose();
    currentUrl.dispose();
    error.dispose();
  }
}

/// Holds the browser's tab state so bookmarks opened while the browser is
/// already visible spawn new tabs instead of hijacking the current page.
class BrowserController extends ChangeNotifier {
  BrowserController._();

  static final BrowserController instance = BrowserController._();

  final List<BrowserTab> _tabs = <BrowserTab>[];
  int _activeIndex = 0;

  List<BrowserTab> get tabs => List<BrowserTab>.unmodifiable(_tabs);

  int get activeIndex => _activeIndex;

  bool get isOpen => _tabs.isNotEmpty;

  BrowserTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Opens [url] in a new tab (or focuses it if already open).
  Future<void> openUrl(String url, {String title = 'New Tab'}) async {
    final int existing = _tabs.indexWhere((BrowserTab t) => t.homeUrl == url);
    if (existing >= 0) {
      _activeIndex = existing;
      notifyListeners();
      return;
    }
    final BrowserTab tab = BrowserTab(homeUrl: url, title: title);
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    await tab.initialize();
    notifyListeners();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  Future<void> closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final BrowserTab tab = _tabs.removeAt(index);
    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.isEmpty ? 0 : _tabs.length - 1;
    }
    notifyListeners();
    await tab.dispose();
  }

  /// Closes the browser entirely, destroying every controller and freeing
  /// the RAM so SALU stays lightweight (Phase 6 · Memory Management).
  Future<void> closeBrowser() async {
    final List<BrowserTab> tabs = List<BrowserTab>.from(_tabs);
    _tabs.clear();
    _activeIndex = 0;
    notifyListeners();
    for (final BrowserTab tab in tabs) {
      await tab.dispose();
    }
  }
}

/// The built-in browser (Phase 6 · Step 4).
///
/// Fills the whole window while open. SALU's OSC is hidden in this mode —
/// the streaming site supplies its own player controls.
class BrowserScreen extends StatelessWidget {
  const BrowserScreen({super.key, required this.onCloseBrowser});

  final VoidCallback onCloseBrowser;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrowserController.instance,
      builder: (BuildContext context, Widget? _) {
        final BrowserController browser = BrowserController.instance;
        if (!browser.isOpen) return const SizedBox.shrink();

        return Container(
          color: AppColors.background,
          child: Column(
            children: <Widget>[
              _TabBar(browser: browser, onCloseBrowser: onCloseBrowser),
              const Divider(height: 1),
              Expanded(
                child: _TabBody(
                  key: ValueKey<BrowserTab>(browser.activeTab!),
                  tab: browser.activeTab!,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.browser, required this.onCloseBrowser});

  final BrowserController browser;
  final VoidCallback onCloseBrowser;

  @override
  Widget build(BuildContext context) {
    final BrowserTab? active = browser.activeTab;
    return Container(
      height: 46,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          _NavButton(
            icon: Icons.home_rounded,
            tooltip: 'Home',
            onPressed: active == null
                ? null
                : () => active.controller.loadUrl(active.homeUrl),
          ),
          _NavButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed:
                active == null ? null : () => active.controller.goBack(),
          ),
          _NavButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Forward',
            onPressed:
                active == null ? null : () => active.controller.goForward(),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: AppColors.divider),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: browser.tabs.length,
              itemBuilder: (BuildContext context, int index) {
                final BrowserTab tab = browser.tabs[index];
                final bool selected = index == browser.activeIndex;
                return ValueListenableBuilder<String>(
                  valueListenable: tab.title,
                  builder: (BuildContext context, String title, Widget? _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 6),
                      child: Material(
                        color: selected
                            ? AppColors.surfaceHighlight
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => browser.selectTab(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 170),
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: selected
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => browser.closeTab(index),
                                  child: const Icon(Icons.close_rounded,
                                      size: 14,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          _NavButton(
            icon: Icons.bookmark_add_outlined,
            tooltip: 'Bookmark this page',
            onPressed: active == null
                ? null
                : () {
                    final String? err = StreamManager.instance.addBookmark(
                      active.title.value,
                      active.currentUrl.value,
                    );
                    OsdController.instance.show(
                      err ?? 'Bookmark saved',
                      icon: err == null
                          ? Icons.check_rounded
                          : Icons.error_outline_rounded,
                    );
                  },
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onCloseBrowser,
            icon: const Icon(Icons.close_fullscreen_rounded, size: 17),
            label: const Text('Close Browser'),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 19,
      color: AppColors.textPrimary,
      disabledColor: AppColors.textSecondary,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _TabBody extends StatefulWidget {
  const _TabBody({super.key, required this.tab});

  final BrowserTab tab;

  @override
  State<_TabBody> createState() => _TabBodyState();
}

class _TabBodyState extends State<_TabBody> {
  @override
  void initState() {
    super.initState();
    widget.tab.initialize();
  }

  @override
  void didUpdateWidget(_TabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      widget.tab.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: widget.tab.error,
      builder: (BuildContext context, String? error, Widget? _) {
        if (error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textSecondary),
              ),
            ),
          );
        }
        // Rebuilds as soon as the platform view reports it is initialized.
        return ValueListenableBuilder<WebviewValue>(
          valueListenable: widget.tab.controller,
          builder: (BuildContext context, WebviewValue value, Widget? _) {
            if (!value.isInitialized) {
              return const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return Webview(widget.tab.controller);
          },
        );
      },
    );
  }
}
