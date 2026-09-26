import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/browser_service.dart';
import 'package:salu/core/remote/remote_command_handler.dart';
import 'package:salu/core/remote/remote_protocol.dart';
import 'package:salu/core/remote/remote_service.dart';
import 'package:salu/core/remote/remote_web_media_bridge.dart';

/// The one fullscreen seat (pc_part.md C1 · remote.md §17.14.1): the PC
/// picks the target — the page's player when it has one (injected request
/// first, then a REAL click on the player's own control when the page
/// refused it), the SALU window only when it has not — `on:false` leaves
/// both, and the ack's `target` names what actually happened.
///
/// Every seam is faked: [_Page] plays the document (its fullscreen state,
/// what the plan script finds, whether the injected request took), [_Host]
/// plays the browser host's ContainsFullScreenElement truth and the window.
class _Page {
  bool hasPlayer = true;
  bool hasControl = true;
  bool acceptsInjected = false;
  bool clickWorks = true;
  bool fullscreen = false;
  final List<String> scripts = <String>[];

  Future<Object?> run(String script) async {
    if (script == RemoteWebMediaScripts.fullscreenState) return fullscreen;
    if (script == RemoteWebMediaScripts.fullscreenPlan()) {
      scripts.add('plan');
      if (!hasPlayer) return <String, Object?>{'found': false};
      if (fullscreen) {
        return <String, Object?>{'found': true, 'fullscreen': true};
      }
      if (acceptsInjected) fullscreen = true;
      return <String, Object?>{
        'found': true,
        'fullscreen': false,
        'requested': true,
        'control': hasControl
            ? <String, Object?>{'x': 1080, 'y': 657, 'via': '.ytp-fullscreen-button'}
            : null,
      };
    }
    scripts.add('other');
    return null;
  }
}

class _Host {
  _Host(this.page);

  final _Page page;
  bool window = false;
  final List<(double, double)> clicks = <(double, double)>[];
  int exits = 0;
  final List<bool> windowSets = <bool>[];

  Future<bool> click(double x, double y) async {
    clicks.add((x, y));
    if (page.clickWorks) page.fullscreen = true;
    return true;
  }

  Future<void> exitPage() async {
    exits++;
    page.fullscreen = false;
  }

  Future<void> setWindow(bool on) async {
    windowSets.add(on);
    window = on;
  }

  RemoteWebFullscreen seat({bool web = true}) => RemoteWebFullscreen(
        executeScript: web ? page.run : null,
        pageClick: web ? click : null,
        pageFullscreen: () => page.fullscreen,
        exitPage: exitPage,
        windowFullscreen: () => window,
        setWindowFullscreen: setWindow,
        poll: Duration.zero,
        injectedWait: Duration.zero,
        clickWait: Duration.zero,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('target selection', () {
    test('a player that refuses the injected call → real click → page',
        () async {
      final _Page page = _Page();
      final _Host host = _Host(page);
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(out.fullscreen, isTrue);
      expect(out.target, 'page');
      // The YouTube fix: the real-input fallback was used, at the control.
      expect(host.clicks, <(double, double)>[(1080.0, 657.0)]);
      expect(host.windowSets, isEmpty);
    });

    test('a player that accepts the injected call needs no click', () async {
      final _Page page = _Page()..acceptsInjected = true;
      final _Host host = _Host(page);
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(out.target, 'page');
      expect(out.fullscreen, isTrue);
      expect(host.clicks, isEmpty);
    });

    test('no player → the SALU window, exactly once', () async {
      final _Page page = _Page()..hasPlayer = false;
      final _Host host = _Host(page);
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(out.target, 'window');
      expect(out.fullscreen, isTrue);
      expect(host.windowSets, <bool>[true]);
      expect(host.clicks, isEmpty);
    });

    test('outside Web mode (no page at all) → the window', () async {
      final _Page page = _Page();
      final _Host host = _Host(page);
      final RemoteFullscreenOutcome out = await host.seat(web: false).run();
      expect(out.target, 'window');
      expect(host.windowSets, <bool>[true]);
    });

    test('a player whose every attempt is refused falls back to the window, '
        'and the ack says so', () async {
      final _Page page = _Page()..clickWorks = false;
      final _Host host = _Host(page);
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(host.clicks, hasLength(1));
      expect(out.target, 'window');
      expect(out.fullscreen, isTrue);
    });

    test('no reachable control and a refused request → window', () async {
      final _Page page = _Page()..hasControl = false;
      final _Host host = _Host(page);
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(host.clicks, isEmpty);
      expect(out.target, 'window');
    });
  });

  group('leaving', () {
    test('toggle while the page is fullscreen leaves the page and the window',
        () async {
      final _Page page = _Page()..fullscreen = true;
      final _Host host = _Host(page)..window = true; // the host's hand-off
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(out.fullscreen, isFalse);
      expect(out.target, 'page');
      expect(host.exits, 1);
      expect(host.window, isFalse);
    });

    test('toggle while only the window is fullscreen leaves the window',
        () async {
      final _Page page = _Page();
      final _Host host = _Host(page)..window = true;
      final RemoteFullscreenOutcome out = await host.seat().run();
      expect(out, isA<RemoteFullscreenOutcome>());
      expect(out.fullscreen, isFalse);
      expect(out.target, 'window');
      expect(host.exits, 0);
      expect(host.windowSets, <bool>[false]);
    });

    test('on:false always leaves both, even when asked twice', () async {
      final _Page page = _Page()..fullscreen = true;
      final _Host host = _Host(page)..window = true;
      await host.seat().run(on: false);
      final RemoteFullscreenOutcome again = await host.seat().run(on: false);
      expect(page.fullscreen, isFalse);
      expect(host.window, isFalse);
      expect(again.fullscreen, isFalse);
    });

    test('on:true while already page-fullscreen is a no-op "page"', () async {
      final _Page page = _Page()..fullscreen = true;
      final _Host host = _Host(page)..window = true;
      final RemoteFullscreenOutcome out = await host.seat().run(on: true);
      expect(out.target, 'page');
      expect(out.fullscreen, isTrue);
      expect(host.clicks, isEmpty);
      expect(host.exits, 0);
    });
  });

  group('the verb', () {
    test('web_fullscreen acks {fullscreen, target}', () async {
      final _Page page = _Page();
      final _Host host = _Host(page);
      final RemoteCommandHandler handler =
          RemoteCommandHandler(webFullscreen: host.seat());
      final RemoteCommandResponse reply = await handler
          .handle(const RemoteCommand(id: 1, verb: 'web_fullscreen'));
      expect(reply.ok, isTrue);
      expect(reply.result, <String, Object?>{
        'fullscreen': true,
        'target': 'page',
      });
    });

    test('a non-bool `on` is invalid_arguments', () async {
      final RemoteCommandHandler handler =
          RemoteCommandHandler(webFullscreen: _Host(_Page()).seat());
      final RemoteCommandResponse reply = await handler.handle(
        const RemoteCommand(
          id: 2,
          verb: 'web_fullscreen',
          args: <String, Object?>{'on': 'yes'},
        ),
      );
      expect(reply.code, RemoteErrorCode.invalidArguments);
    });

    test('web_media_get reports `fullscreen`', () async {
      BrowserService.instance.pageFullscreen.value = false;
      final RemoteCommandHandler handler = RemoteCommandHandler(
        webMedia: RemoteWebMediaBridge(
          executeScript: (String _) async => <String, Object?>{
            'found': true,
            'playing': true,
            'position': 1000,
            'duration': 2000,
            'volume': 50,
            'fullscreen': true,
          },
        ),
      );
      final RemoteCommandResponse reply = await handler
          .handle(const RemoteCommand(id: 3, verb: 'web_media_get'));
      expect(reply.ok, isTrue);
      expect(reply.result!['fullscreen'], isTrue);
      expect(reply.result!['canFull'], isFalse);
    });

    test('web_media_get follows the host when the document lags', () async {
      BrowserService.instance.pageFullscreen.value = true;
      addTearDown(() => BrowserService.instance.pageFullscreen.value = false);
      final RemoteCommandHandler handler = RemoteCommandHandler(
        webMedia: RemoteWebMediaBridge(
          executeScript: (String _) async =>
              <String, Object?>{'found': true, 'fullscreen': false},
        ),
      );
      final RemoteCommandResponse reply = await handler
          .handle(const RemoteCommand(id: 4, verb: 'web_media_get'));
      expect(reply.result!['fullscreen'], isTrue);
    });
  });

  group('the plan script', () {
    test('searches the player\'s own control, both spellings, no "exit"', () {
      final String js = RemoteWebMediaScripts.fullscreenPlan();
      expect(js, contains('.ytp-fullscreen-button'));
      expect(js, contains('[aria-label*="full screen" i]'));
      expect(js, contains('[aria-label*="fullscreen" i]'));
      expect(js, contains("indexOf('exit')"));
      // Device pixels of the view — the host divides by its own ratio.
      expect(js, contains('devicePixelRatio'));
      expect(js, contains('requestFullscreen'));
    });
  });

  group('features and routing', () {
    test('Part C and D flags are advertised; web_mouse and pc_power conditional', () {
      final List<String> on = RemoteService.helloFeatures(mouse: true, power: true);
      expect(on, containsAll(<String>[
        'web_home',
        'web_fullscreen',
        'web_mouse',
        'web_bookmark_add',
        'pc_power',
      ]));
      final List<String> off = RemoteService.helloFeatures(mouse: false, power: false);
      expect(off, isNot(contains('web_mouse')));
      expect(off, isNot(contains('pc_power')));
      expect(off, contains('web_fullscreen'));
    });

    test('browser_nav accepts home; an unknown action stays invalid',
        () async {
      final List<String> seen = <String>[];
      BrowserService.instance.setRemoteHandlers(
        navigate: (String action) async => seen.add(action),
        executeScript: (String _) async => null,
      );
      addTearDown(BrowserService.instance.setRemoteHandlers);
      final RemoteCommandHandler handler = RemoteCommandHandler();
      final RemoteCommandResponse home = await handler.handle(
        const RemoteCommand(
          id: 5,
          verb: 'browser_nav',
          args: <String, Object?>{'action': 'home'},
        ),
      );
      expect(home.ok, isTrue);
      expect(seen, <String>['home']);
      final RemoteCommandResponse bad = await handler.handle(
        const RemoteCommand(
          id: 6,
          verb: 'browser_nav',
          args: <String, Object?>{'action': 'sideways'},
        ),
      );
      expect(bad.code, RemoteErrorCode.invalidArguments);
    });
  });
}
