import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/remote/remote_firewall.dart';

/// The firewall handshake's decision layer (remote.md §8.3, amended
/// 2026-09-21). The probes and fixes themselves are Windows-only PowerShell
/// — what these tests pin is everything Windows can answer with and every
/// answer SALU gives back: the rule evaluation (including the Cancel trap
/// and the moved-build trap), the JSON the probe half-parses badly, and the
/// elevation dance, end to end through the service's seams.

RemoteFirewallRule rule({
  String name = 'SALU',
  String displayName = 'SALU',
  String action = 'Allow',
  bool enabled = true,
  String direction = 'Inbound',
  String profile = 'Private',
  String program = r'C:\Apps\Salu\salu.exe',
}) =>
    RemoteFirewallRule(
      name: name,
      displayName: displayName,
      action: action,
      enabled: enabled,
      direction: direction,
      profile: profile,
      program: program,
    );

const String exe = r'C:\Apps\Salu\salu.exe';

void main() {
  group('evaluateFirewallReport', () {
    test('no rules at all → missing', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: const <RemoteFirewallRule>[],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.missing);
      expect(status.needsRuleFix, isTrue);
      expect(status.needsAttention, isTrue);
    });

    test('enabled inbound private allow for the running exe → ok', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule()],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.ok);
      expect(status.needsAttention, isFalse);
    });

    test('rule paths compare case- and separator-insensitively', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: r'c:\apps\salu\salu.exe',
        rules: <RemoteFirewallRule>[rule(program: r'C:\APPS\SALU\salu.exe')],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.ok);
    });

    test('a Public-only allow is no allow → missing', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule(profile: 'Public')],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.missing);
      expect(status.needsRuleFix, isTrue);
    });

    test('a disabled allow is no allow → missing', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule(enabled: false)],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.missing);
    });

    test('an outbound allow does not count → missing', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule(direction: 'Outbound')],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.missing);
    });

    test('profile Any covers Private → ok and covered on Public networks', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule(profile: 'Any')],
        profiles: const <RemoteNetworkProfileInfo>[
          RemoteNetworkProfileInfo(alias: 'Wi-Fi', category: 'Public'),
        ],
      );
      expect(status.ruleState, RemoteFirewallRuleState.ok);
      expect(status.coveredOnPublic, isTrue);
      expect(status.needsPrivateNetwork, isFalse);
      expect(status.needsAttention, isFalse);
    });

    test('the Cancel trap: an enabled block beats every allow → blocked', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[
          rule(),
          rule(name: 'salu', action: 'Block', profile: 'Any'),
        ],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.blocked);
      expect(status.needsRuleFix, isTrue);
    });

    test('a disabled block is history, not a trap', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[
          rule(),
          rule(action: 'Block', enabled: false),
        ],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.ok);
    });

    test('the moved-build trap: same exe name at a dead path → stalePath', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[
          rule(name: 'salu', program: r'D:\Old\SALU-0.9\salu.exe'),
        ],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.stalePath);
      expect(status.needsRuleFix, isTrue);
    });

    test('someone else entirely is not our business → missing', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[
          rule(name: 'Lively', program: r'C:\Tools\Lively\lively.exe'),
        ],
        profiles: const <RemoteNetworkProfileInfo>[],
      );
      expect(status.ruleState, RemoteFirewallRuleState.missing);
    });

    test('Public Wi-Fi with only a Private rule → needs the profile ask', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule()],
        profiles: const <RemoteNetworkProfileInfo>[
          RemoteNetworkProfileInfo(alias: 'Wi-Fi', category: 'Public'),
          RemoteNetworkProfileInfo(alias: 'Ethernet', category: 'Private'),
        ],
      );
      expect(status.ruleState, RemoteFirewallRuleState.ok);
      expect(status.publicAliases, <String>['Wi-Fi']);
      expect(status.needsRuleFix, isFalse);
      expect(status.needsPrivateNetwork, isTrue);
      expect(status.needsAttention, isTrue);
    });

    test('Private networks raise no profile ask', () {
      final RemoteFirewallStatus status = evaluateFirewallReport(
        exePath: exe,
        rules: <RemoteFirewallRule>[rule()],
        profiles: const <RemoteNetworkProfileInfo>[
          RemoteNetworkProfileInfo(alias: 'Wi-Fi', category: 'Private'),
        ],
      );
      expect(status.publicAliases, isEmpty);
      expect(status.needsAttention, isFalse);
    });
  });

  group('parseFirewallReportBody', () {
    test('a full answer parses', () {
      const String body = '{"ok":true,"rules":[{"name":"SALU","displayName":'
          '"SALU","action":"Allow","enabled":true,"direction":"Inbound",'
          '"profile":"Private","program":"C:\\\\Apps\\\\Salu\\\\salu.exe"}],'
          '"profiles":[{"alias":"Wi-Fi","category":"Private"}]}';
      final RemoteFirewallProbe? probe = parseFirewallReportBody(body);
      expect(probe, isNotNull);
      expect(probe!.ok, isTrue);
      expect(probe.rules, hasLength(1));
      expect(probe.rules.single.program, r'C:\Apps\Salu\salu.exe');
      expect(probe.rules.single.enabled, isTrue);
      expect(probe.profiles.single.alias, 'Wi-Fi');
    });

    test('PowerShell unwraps one-element arrays — objects still parse', () {
      const String body = '{"ok":true,'
          '"rules":{"name":"SALU","displayName":"SALU","action":"Block",'
          '"enabled":true,"direction":"Inbound","profile":"Any",'
          '"program":"C:\\\\Apps\\\\Salu\\\\salu.exe"},'
          '"profiles":{"alias":"Wi-Fi","category":"Public"}}';
      final RemoteFirewallProbe? probe = parseFirewallReportBody(body);
      expect(probe, isNotNull);
      expect(probe!.rules, hasLength(1));
      expect(probe.rules.single.action, 'Block');
      expect(probe.profiles.single.category, 'Public');
    });

    test('a failed probe keeps Windows’ message', () {
      const String body =
          '{"ok":false,"error":"The service cannot be started"}';
      final RemoteFirewallProbe? probe = parseFirewallReportBody(body);
      expect(probe, isNotNull);
      expect(probe!.ok, isFalse);
      expect(probe.error, contains('cannot be started'));
      expect(probe.rules, isEmpty);
    });

    test('empty and garbage bodies are unreadable, not crashes', () {
      expect(parseFirewallReportBody(''), isNull);
      expect(parseFirewallReportBody('   '), isNull);
      expect(parseFirewallReportBody('not json at all'), isNull);
    });

    test('a warning line ahead of the JSON is skipped', () {
      const String body = 'WARNING: Something chatty.\n'
          '{"ok":true,"rules":[],"profiles":[]}';
      final RemoteFirewallProbe? probe = parseFirewallReportBody(body);
      expect(probe, isNotNull);
      expect(probe!.ok, isTrue);
      expect(probe.rules, isEmpty);
    });

    test('a UTF-8 BOM ahead of the JSON is ignored', () {
      const String body = '\uFEFF{"ok":true,"rules":[],"profiles":[]}';
      final RemoteFirewallProbe? probe = parseFirewallReportBody(body);
      expect(probe, isNotNull);
      expect(probe!.ok, isTrue);
    });

    test('missing sections answer as empty', () {
      final RemoteFirewallProbe? probe =
          parseFirewallReportBody('{"ok":true}');
      expect(probe, isNotNull);
      expect(probe!.rules, isEmpty);
      expect(probe.profiles, isEmpty);
    });
  });

  group('the port window', () {
    test('the preferred port leads its nine retry neighbours (§8.1)', () {
      expect(remoteFirewallPortRange(7258), '7258-7267');
    });

    test('the window never leaves the valid port space', () {
      expect(remoteFirewallPortRange(65530), '65530-65535');
      expect(remoteFirewallPortRange(65535), '65535');
      expect(remoteFirewallPortRange(80), '1024-1033');
    });
  });

  group('the PowerShell scripts', () {
    test('the detect script carries the exe path, quotes escaped', () {
      final String script =
          buildFirewallDetectScript(r"C:\Kat's PC\Salu\salu.exe");
      expect(script, contains(r"C:\Kat''s PC\Salu\salu.exe"));
      expect(script, contains('Get-NetFirewallApplicationFilter'));
      expect(script, contains('Get-NetConnectionProfile'));
      expect(script, contains('ConvertTo-Json'));
    });

    test('the fix script removes, re-allows and optionally flips profiles', () {
      final String withFlip = buildFirewallFixScript(
        exePath: exe,
        portRange: '7258-7267',
        makePrivate: true,
      );
      expect(withFlip, contains('Remove-NetFirewallRule'));
      expect(withFlip, contains('New-NetFirewallRule'));
      expect(withFlip, contains("'7258-7267'"));
      expect(withFlip, contains('-Profile Private'));
      expect(withFlip, contains('Set-NetConnectionProfile'));
      expect(withFlip, contains(r'if ($true)'));

      final String withoutFlip = buildFirewallFixScript(
        exePath: exe,
        portRange: '7258-7267',
        makePrivate: false,
      );
      expect(withoutFlip, contains(r'if ($false)'));
    });
  });

  group('encodePsCommand', () {
    test('is base64 of UTF-16LE — PowerShell’s EncodedCommand envelope', () {
      expect(encodePsCommand('A'), base64Encode(const <int>[0x41, 0x00]));
    });

    test('round-trips through the byte pairs', () {
      const String command = r"\$x='SALU'; exit 0";
      final List<int> bytes = base64Decode(encodePsCommand(command));
      expect(bytes.length, command.length * 2);
      final StringBuffer back = StringBuffer();
      for (int i = 0; i < bytes.length; i += 2) {
        back.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
      }
      expect(back.toString(), command);
    });
  });

  group('remoteFirewallSamePath', () {
    test('case and separators never change identity', () {
      expect(remoteFirewallSamePath(r'C:\A\salu.exe', r'c:\a\salu.exe'), isTrue);
      expect(remoteFirewallSamePath(r'C:\A\salu.exe', 'C:/A/salu.exe'), isTrue);
      expect(remoteFirewallSamePath(r'C:\A\salu.exe', r'C:\B\salu.exe'), isFalse);
    });
  });

  group('RemoteFirewallService (seams)', () {
    late RemoteFirewallService service;

    RemoteFirewallProbe healthyProbe() => RemoteFirewallProbe(
          ok: true,
          rules: <RemoteFirewallRule>[rule()],
        );

    ProcessResult probeResult(RemoteFirewallProbe probe) => ProcessResult(
          0,
          0,
          jsonEncode(<String, Object?>{
            'ok': probe.ok,
            'error': probe.error,
            'rules': probe.rules
                .map((RemoteFirewallRule r) => <String, Object?>{
                      'name': r.name,
                      'displayName': r.displayName,
                      'action': r.action,
                      'enabled': r.enabled,
                      'direction': r.direction,
                      'profile': r.profile,
                      'program': r.program,
                    })
                .toList(),
            'profiles': probe.profiles
                .map((RemoteNetworkProfileInfo p) => <String, String>{
                      'alias': p.alias,
                      'category': p.category,
                    })
                .toList(),
          }),
          '',
        );

    late RemoteFirewallRunner originalRunner;

    setUp(() {
      service = RemoteFirewallService.instance;
      originalRunner = service.runner;
      service.exePathOf = () => exe;
      service.isWindowsOf = () => true;
      service.preferredPortOf = () => 7258;
      service.status.value = RemoteFirewallStatus.unknown();
      service.applying.value = false;
    });

    tearDown(() {
      // Leave the singleton the way the app found it.
      service.runner = originalRunner;
      service.isWindowsOf = () => Platform.isWindows;
      service.exePathOf = () => Platform.resolvedExecutable;
      service.preferredPortOf = null;
      service.status.value = RemoteFirewallStatus.unknown();
    });

    test('off Windows the answer is a quiet unknown', () async {
      service.isWindowsOf = () => false;
      service.runner = (String e, List<String> a, {Encoding? stdoutEncoding}) =>
          throw StateError('must not run');
      final RemoteFirewallStatus status = await service.recheck(force: true);
      expect(status.ruleState, RemoteFirewallRuleState.unknown);
      expect(status.needsAttention, isFalse);
    });

    test('recheck evaluates the probe and publishes it', () async {
      service.runner = (String e, List<String> a,
          {Encoding? stdoutEncoding}) async {
        expect(e, 'powershell');
        expect(a, contains('-Command'));
        return probeResult(healthyProbe());
      };
      final RemoteFirewallStatus status = await service.recheck(force: true);
      expect(status.ruleState, RemoteFirewallRuleState.ok);
      expect(service.status.value.ruleState, RemoteFirewallRuleState.ok);
    });

    test('a Cancel-trap probe publishes blocked', () async {
      service.runner = (String e, List<String> a,
              {Encoding? stdoutEncoding}) async =>
          probeResult(RemoteFirewallProbe(ok: true, rules: <RemoteFirewallRule>[
            rule(name: 'salu', action: 'Block', profile: 'Any'),
          ]));
      final RemoteFirewallStatus status = await service.recheck(force: true);
      expect(status.ruleState, RemoteFirewallRuleState.blocked);
      expect(status.needsAttention, isTrue);
    });

    test('a failed probe answers unknown and never names a fix', () async {
      service.runner = (String e, List<String> a,
              {Encoding? stdoutEncoding}) async =>
          ProcessResult(0, 1, '{"ok":false,"error":"service off"}', '');
      final RemoteFirewallStatus status = await service.recheck(force: true);
      expect(status.ruleState, RemoteFirewallRuleState.unknown);
      expect(status.detail, contains('service off'));
      expect(status.needsAttention, isFalse);
    });

    test('recheck reuses a fresh probe unless forced', () async {
      int calls = 0;
      service.runner = (String e, List<String> a,
          {Encoding? stdoutEncoding}) async {
        calls++;
        return probeResult(healthyProbe());
      };
      await service.recheck(force: true);
      await service.recheck();
      expect(calls, 1);
      await service.recheck(force: true);
      expect(calls, 2);
    });

    test('a declined UAC is cancelled, and the busy flag always drops', () async {
      service.runner = (String e, List<String> a,
          {Encoding? stdoutEncoding}) async {
        // The elevation call is the one carrying the encoded fix.
        expect(a.last, contains('EncodedCommand'));
        return ProcessResult(
            0, 1, '', 'The operation was canceled by the user');
      };
      final RemoteFirewallFixResult result =
          await service.fix(makePrivate: false);
      expect(result.outcome, RemoteFirewallFixOutcome.cancelled);
      expect(service.applying.value, isFalse);
    });

    test('an accepted UAC is verified by a fresh probe before green', () async {
      final List<String> elevationArgs = <String>[];
      service.runner = (String e, List<String> a,
          {Encoding? stdoutEncoding}) async {
        if (a.any((String item) => item.contains('EncodedCommand'))) {
          elevationArgs.addAll(a);
          return ProcessResult(0, 0, '', '');
        }
        return probeResult(healthyProbe());
      };
      final RemoteFirewallFixResult result =
          await service.fix(makePrivate: true);
      expect(result.outcome, RemoteFirewallFixOutcome.applied);
      expect(service.applying.value, isFalse);
      expect(service.status.value.ruleState, RemoteFirewallRuleState.ok);
      // The elevation really is an elevation: RunAs verb + the script is
      // base64, so nothing in the command line needs shell escaping.
      final String outer = elevationArgs.last;
      expect(outer, contains('-Verb RunAs'));
      expect(outer, isNot(contains('New-NetFirewallRule')));
    });

    test('an accepted UAC that changed nothing is a failure, not a green',
        () async {
      service.runner = (String e, List<String> a,
          {Encoding? stdoutEncoding}) async {
        if (a.any((String item) => item.contains('EncodedCommand'))) {
          return ProcessResult(0, 0, '', '');
        }
        return ProcessResult(
            0, 0, '{"ok":true,"rules":[],"profiles":[]}', '');
      };
      final RemoteFirewallFixResult result =
          await service.fix(makePrivate: false);
      expect(result.outcome, RemoteFirewallFixOutcome.failed);
    });
  });
}
