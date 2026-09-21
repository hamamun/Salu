import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// SALU Remote · Windows Firewall handshake (remote.md §8.3, amended
/// 2026-09-21).
///
/// **The one fact this file is built around:** if the firewall blocks SALU,
/// the phone's hello never reaches the PC, so SALU can never know anyone
/// tried. The firewall question must therefore be asked when the feature is
/// switched on — never when the first connection arrives.
///
/// This is the Plex / KDE Connect tier: on Remote ON (and on every launch
/// while Remote is enabled) SALU checks whether an inbound Allow rule covers
/// the *running* exe and, if not, asks in its own dialog. One [Allow] press
/// → one Windows UAC → the rule is written (program + TCP + the remote port
/// range, Private profile) → verified. It also covers the three classic
/// traps:
///
///  * **The Cancel trap** — clicking Cancel on Windows' own "Allow access?"
///    popup silently writes a permanent *Block* rule and Windows never asks
///    again; "allow the app later" in the control panel cannot beat it. A
///    Block rule must be found and removed, which is fixable ([blocked]).
///  * **The stale rule** — the rule points at an exe *path*; a moved folder
///    or a replaced portable build leaves it dead ([stalePath]).
///  * **Public network profile** — a Private-scoped rule does nothing while
///    the Wi-Fi is marked Public, so the dialog offers to flip the profile
///    in the same elevated step, with consent.
///
/// What SALU cannot fix programmatically (third-party antivirus firewalls,
/// group policy, the firewall service itself switched off) still degrades
/// to the original 90-second panel hint + "Open firewall settings" button —
/// the query simply reports [RemoteFirewallRuleState.unknown].
///
/// Everything below the [RemoteFirewallService] class is pure: parsing the
/// probe JSON, evaluating what the rules mean, and building the PowerShell
/// scripts. The service is the only piece that touches the OS, so the logic
/// runs in plain unit tests (test/remote_firewall_test.dart).

/// What the firewall currently means for the phone remote.
enum RemoteFirewallRuleState {
  /// Never queried, or the query failed (firewall service off, third-party
  /// firewall owns the machine, not Windows). Honest answer: the 90-second
  /// hint only — no claims either way.
  unknown,

  /// An enabled inbound Allow rule covers the running exe on private
  /// networks. Nothing to do.
  ok,

  /// No covering Allow rule exists and no Block rule was found.
  missing,

  /// An enabled inbound **Block** rule points at the running exe — the
  /// Windows Security "Cancel" trap. A block beats every allow, so this is
  /// reported ahead of [ok]: removing the block is the fix.
  blocked,

  /// Inbound rules exist for the same exe filename at *other* paths (the
  /// folder moved, or a new portable build landed), but none matches the
  /// running exe — the old rule is dead. Re-adding at the current path is
  /// the fix.
  stalePath,
}

/// One inbound firewall rule, as the probe reports it.
class RemoteFirewallRule {
  const RemoteFirewallRule({
    required this.name,
    required this.displayName,
    required this.action,
    required this.enabled,
    required this.direction,
    required this.profile,
    required this.program,
  });

  final String name;
  final String displayName;
  final String action;
  final bool enabled;
  final String direction;
  final String profile;
  final String program;

  bool get isInbound => direction.toLowerCase() == 'inbound';
  bool get isAllow => action.toLowerCase() == 'allow';
  bool get isBlock => action.toLowerCase() == 'block';

  /// Windows reports the profile as a flag string ("Any", "Private",
  /// "Private, Public", …). A rule covering Any covers Private too.
  bool get coversPrivate {
    final List<String> parts =
        profile.split(',').map((String p) => p.trim().toLowerCase()).toList();
    return parts.contains('any') || parts.contains('private');
  }

  bool get coversAny {
    final List<String> parts =
        profile.split(',').map((String p) => p.trim().toLowerCase()).toList();
    return parts.contains('any');
  }
}

/// One connected Windows network profile (Get-NetConnectionProfile).
class RemoteNetworkProfileInfo {
  const RemoteNetworkProfileInfo({required this.alias, required this.category});

  final String alias;
  final String category;

  bool get isPublic => category.toLowerCase() == 'public';
}

/// The evaluated answer the UI reads. Immutable; every successful or failed
/// probe publishes a fresh one.
class RemoteFirewallStatus {
  const RemoteFirewallStatus({
    required this.ruleState,
    this.publicAliases = const <String>[],
    this.coveredOnPublic = false,
    this.detail,
    this.checked = false,
    this.checkedAt,
  });

  /// The state before — and after a failed — query. Before any check the
  /// [checkedAt] stays null so the freshness window can never suppress the
  /// very first probe.
  factory RemoteFirewallStatus.unknown({String? detail}) =>
      RemoteFirewallStatus(
        ruleState: RemoteFirewallRuleState.unknown,
        detail: detail,
        checked: detail != null,
        checkedAt: detail == null ? null : DateTime.now(),
      );

  final RemoteFirewallRuleState ruleState;

  /// Interface aliases whose network category is Public (the Wi-Fi profile
  /// trap). Empty on private-only machines and when the query failed.
  final List<String> publicAliases;

  /// An enabled inbound Allow for the running exe covers the Any profile, so
  /// it keeps working even on Public networks.
  final bool coveredOnPublic;

  /// The failure's message when [ruleState] is [RemoteFirewallRuleState.unknown]
  /// after a real probe — surfaced in logs, never in copy.
  final String? detail;

  /// A completed query has happened (true even when it failed).
  final bool checked;
  final DateTime? checkedAt;

  /// The Private-scoped rule story is broken: nothing allows SALU, or
  /// something actively blocks it, or the only rule belongs to a dead path.
  bool get needsRuleFix =>
      ruleState == RemoteFirewallRuleState.missing ||
      ruleState == RemoteFirewallRuleState.blocked ||
      ruleState == RemoteFirewallRuleState.stalePath;

  /// The Wi-Fi is Public and no Any-scoped allow covers SALU there — the
  /// Private rule cannot help until the profile (or the scope) changes.
  bool get needsPrivateNetwork => publicAliases.isNotEmpty && !coveredOnPublic;

  /// Anything the in-app dialog should offer to fix.
  bool get needsAttention => needsRuleFix || needsPrivateNetwork;
}

/// The result of the elevated fix run.
enum RemoteFirewallFixOutcome {
  /// Windows applied the change and the re-check sees the new rule.
  applied,

  /// The UAC prompt was declined or closed — nothing changed.
  cancelled,

  /// The elevated step or the re-check failed (group policy, antivirus
  /// firewall, …). The detail line carries Windows' message when we have it.
  failed,
}

class RemoteFirewallFixResult {
  const RemoteFirewallFixResult(this.outcome, {this.detail});

  final RemoteFirewallFixOutcome outcome;
  final String? detail;
}

// ── Pure policy below — no dart:io beyond types, one test file proves it ──

/// Rule name SALU owns. Anything by this name is ours to replace; the
/// fix also sweeps same-filename rules so stale portable paths and block
/// traps leave cleanly.
const String remoteFirewallRuleName = 'SALU';

/// The local-port window the allow rule carries: the preferred remote port
/// plus SALU's own fallback walk (remote.md §8.1 — "If busy: try 7259 …
/// 7267"). QR payloads always carry the real bound port, so every realistic
/// bind stays inside the rule; the last-resort OS-assigned port (all ten
/// busy) degrades to the 90-second hint, exactly as before.
String remoteFirewallPortRange(int preferred) {
  final int clamped = preferred.clamp(1024, 65535);
  final int end = clamped + 9 > 65535 ? 65535 : clamped + 9;
  return end == clamped ? '$clamped' : '$clamped-$end';
}

/// Case-insensitive exe identity — Windows paths and the firewall's stored
/// program strings disagree on casing (and sometimes separators) but never
/// on meaning.
bool remoteFirewallSamePath(String a, String b) =>
    a.replaceAll('/', r'\').toLowerCase() ==
    b.replaceAll('/', r'\').toLowerCase();

String _fileNameOf(String path) {
  final String normalized = path.replaceAll('/', r'\');
  final int cut = normalized.lastIndexOf(r'\');
  return cut < 0 ? normalized : normalized.substring(cut + 1);
}

/// What the probe means for the running exe. Pure — this is the decision
/// every trap flows through, and the tests pin each one.
RemoteFirewallStatus evaluateFirewallReport({
  required String exePath,
  required List<RemoteFirewallRule> rules,
  required List<RemoteNetworkProfileInfo> profiles,
}) {
  final List<RemoteFirewallRule> inbound =
      rules.where((RemoteFirewallRule r) => r.isInbound).toList();
  final List<RemoteFirewallRule> self = inbound
      .where((RemoteFirewallRule r) => remoteFirewallSamePath(r.program, exePath))
      .toList();
  final List<String> publicAliases = profiles
      .where((RemoteNetworkProfileInfo p) => p.isPublic)
      .map((RemoteNetworkProfileInfo p) => p.alias)
      .where((String alias) => alias.isNotEmpty)
      .toList(growable: false);
  final bool coveredOnPublic = self.any(
      (RemoteFirewallRule r) => r.enabled && r.isAllow && r.coversAny);

  final RemoteFirewallRuleState state = () {
    // A block wins over every allow in Windows, so it wins here too — the
    // fix must delete it, not just add an allow beside it.
    if (self.any((RemoteFirewallRule r) => r.enabled && r.isBlock)) {
      return RemoteFirewallRuleState.blocked;
    }
    if (self.any(
        (RemoteFirewallRule r) => r.enabled && r.isAllow && r.coversPrivate)) {
      return RemoteFirewallRuleState.ok;
    }
    // Same exe filename at a path that is not ours: the moved-folder trap.
    final bool staleTwin = inbound.any((RemoteFirewallRule r) =>
        !remoteFirewallSamePath(r.program, exePath) &&
        _fileNameOf(r.program).toLowerCase() ==
            _fileNameOf(exePath).toLowerCase());
    if (staleTwin) return RemoteFirewallRuleState.stalePath;
    return RemoteFirewallRuleState.missing;
  }();

  return RemoteFirewallStatus(
    ruleState: state,
    publicAliases: publicAliases,
    coveredOnPublic: coveredOnPublic,
    checked: true,
    checkedAt: DateTime.now(),
  );
}

/// PowerShell 5.1 serializes a one-element array as the bare object and an
/// empty one as `[]` (or omits it) — normalize every shape to a List.
List<Object?> _asList(Object? value) {
  if (value == null) return const <Object?>[];
  if (value is List) return value.cast<Object?>();
  if (value is Map || value is String) return <Object?>[value];
  return const <Object?>[];
}

String _stringOf(Object? value) => value == null ? '' : '$value';

bool _boolOf(Object? value) {
  if (value is bool) return value;
  return _stringOf(value).toLowerCase() == 'true';
}

/// The decoded probe, kept separate from the evaluation so the parsing quirk
/// surface stays small and testable.
class RemoteFirewallProbe {
  const RemoteFirewallProbe({
    required this.ok,
    this.rules = const <RemoteFirewallRule>[],
    this.profiles = const <RemoteNetworkProfileInfo>[],
    this.error,
  });

  final bool ok;
  final List<RemoteFirewallRule> rules;
  final List<RemoteNetworkProfileInfo> profiles;
  final String? error;
}

/// Parses the probe's stdout (one JSON document). Returns null when the body
/// is not JSON at all — PowerShell then printed something else entirely,
/// which the caller treats as a failed probe.
RemoteFirewallProbe? parseFirewallReportBody(String body) {
  // PowerShell 5.1 may prefix redirected UTF-8 output with a BOM.
  final String trimmed = body.replaceAll('\uFEFF', '').trim();
  if (trimmed.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    // The script may print warnings ahead of the JSON; take the last line
    // that looks like the document before giving up.
    final List<String> lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.startsWith('{') && line.endsWith('}'))
        .toList();
    if (lines.isEmpty) return null;
    try {
      decoded = jsonDecode(lines.last);
    } catch (_) {
      return null;
    }
  }
  if (decoded is! Map) return null;
  final Map<String, Object?> map = decoded.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value));
  if (_boolOf(map['ok']) != true) {
    return RemoteFirewallProbe(ok: false, error: _stringOf(map['error']));
  }
  final List<RemoteFirewallRule> rules = <RemoteFirewallRule>[
    for (final Object? item in _asList(map['rules']))
      if (item is Map)
        RemoteFirewallRule(
          name: _stringOf(item['name']),
          displayName: _stringOf(item['displayName']),
          action: _stringOf(item['action']),
          enabled: _boolOf(item['enabled']),
          direction: _stringOf(item['direction']),
          profile: _stringOf(item['profile']),
          program: _stringOf(item['program']),
        ),
  ];
  final List<RemoteNetworkProfileInfo> profiles = <RemoteNetworkProfileInfo>[
    for (final Object? item in _asList(map['profiles']))
      if (item is Map)
        RemoteNetworkProfileInfo(
          alias: _stringOf(item['alias']),
          category: _stringOf(item['category']),
        ),
  ];
  return RemoteFirewallProbe(ok: true, rules: rules, profiles: profiles);
}

/// Single-quote escaping for embedding a path in a PowerShell string.
String _psString(String value) => value.replaceAll("'", "''");

/// The read-only probe. Needs no administrator rights: enumerating the
/// persistent policy store is allowed for standard users.
///
/// What it answers with is one JSON document: every inbound rule whose
/// program is the running exe or a same-named exe elsewhere (the moved-build
/// trap), plus the connection profiles (the Public-profile trap). Failing
/// any of that — the firewall service off, a third-party suite owning the
/// machine — it answers `{ok:false,error}` and the UI stays quiet.
String buildFirewallDetectScript(String exePath) {
  final String safe = _psString(exePath);
  return '[Console]::OutputEncoding=[Text.Encoding]::UTF8;'
      'try { '
      "\$exe=[Environment]::ExpandEnvironmentVariables('$safe');"
      '\$rules=@();'
      'foreach (\$f in (Get-NetFirewallApplicationFilter -ErrorAction Stop)) { '
      '\$p="";'
      'try { \$p=[Environment]::ExpandEnvironmentVariables([string]\$f.Program) } catch {} '
      'if (\$p.Length -eq 0) { continue } '
      '\$same=(\$p -ieq \$exe);'
      '\$twin=([IO.Path]::GetFileName(\$p) -ieq [IO.Path]::GetFileName(\$exe));'
      'if (-not (\$same -or \$twin)) { continue } '
      '\$r=\$null;'
      'try { \$r=\$f.AssociatedNetFirewallRule } catch {} '
      'if (\$null -eq \$r) { continue } '
      '\$rules+=[PSCustomObject]@{name=[string]\$r.Name;displayName=[string]\$r.DisplayName;'
      'action=[string]\$r.Action;enabled=([string]\$r.Enabled -eq "True");'
      'direction=[string]\$r.Direction;profile=[string]\$r.Profile;program=\$p} '
      '} '
      '\$profiles=@();'
      'foreach (\$c in (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) { '
      '\$profiles+=[PSCustomObject]@{alias=[string]\$c.InterfaceAlias;category=[string]\$c.NetworkCategory} '
      '} '
      '[PSCustomObject]@{ok=\$true;rules=\$rules;profiles=\$profiles} | ConvertTo-Json -Compress -Depth 4 '
      '} catch { '
      '[PSCustomObject]@{ok=\$false;error=[string]\$_.Exception.Message} | ConvertTo-Json -Compress '
      '}';
}

String _psBool(bool value) => value ? '\$true' : '\$false';

/// The elevated fix — one UAC, one atomic story:
///  1. delete every inbound rule naming this exe filename (the Cancel-trap
///     block rules, the dead rules of a moved build) plus any previous
///     SALU-named rule — the fix is idempotent;
///  2. add the allow: this program, TCP, the remote port window, Private
///     profile, enabled;
///  3. with consent, mark Public networks Private (home Wi-Fi).
String buildFirewallFixScript({
  required String exePath,
  required String portRange,
  required bool makePrivate,
}) {
  final String safePath = _psString(exePath);
  final String safeRange = _psString(portRange);
  return "\$exe='$safePath';"
      "\$ruleName='$remoteFirewallRuleName';"
      'try { '
      'foreach (\$f in (Get-NetFirewallApplicationFilter -ErrorAction Stop)) { '
      '\$p="";'
      'try { \$p=[Environment]::ExpandEnvironmentVariables([string]\$f.Program) } catch {} '
      'if (\$p.Length -eq 0) { continue } '
      'if (-not (\$p -ieq \$exe -or [IO.Path]::GetFileName(\$p) -ieq [IO.Path]::GetFileName(\$exe))) { continue } '
      '\$r=\$null;'
      'try { \$r=\$f.AssociatedNetFirewallRule } catch {} '
      'if (\$null -ne \$r -and [string]\$r.Direction -eq "Inbound") { '
      'Remove-NetFirewallRule -Name \$r.Name -ErrorAction SilentlyContinue '
      '} '
      '} '
      'Get-NetFirewallRule -Name \$ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue;'
      'New-NetFirewallRule -Name \$ruleName -DisplayName "SALU" '
      '-Description "Let phones on your Wi-Fi reach the SALU remote." '
      '-Direction Inbound -Action Allow -Program \$exe -Protocol TCP '
      "-LocalPort '$safeRange' -Profile Private -Enabled True | Out-Null;"
      'if (${_psBool(makePrivate)}) { '
      'Get-NetConnectionProfile | Where-Object { \$_.NetworkCategory -eq "Public" } | ForEach-Object { '
      'Set-NetConnectionProfile -InputObject \$_ -NetworkCategory Private -ErrorAction Stop '
      '} '
      '} '
      'exit 0 '
      '} catch { '
      'Write-Host "SALU-FIREWALL-FAILED: \$(\$_.Exception.Message)";'
      'exit 1 '
      '}';
}

/// UTF-16LE + base64 — the `-EncodedCommand` envelope. Quoting a whole
/// script through two nested PowerShell invocations is where bugs breed;
/// an encoded command is opaque ASCII, so nothing needs escaping anywhere.
String encodePsCommand(String command) {
  final List<int> bytes = <int>[];
  for (final int unit in command.codeUnits) {
    bytes.add(unit & 0xFF);
    bytes.add((unit >> 8) & 0xFF);
  }
  return base64Encode(bytes);
}

/// The one piece of the service tests replace: how a process is run.
typedef RemoteFirewallRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
});

Future<ProcessResult> _windowsRunner(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    stdoutEncoding: stdoutEncoding ?? systemEncoding,
    stderrEncoding: systemEncoding,
  );
}

/// The Windows-half of the handshake. Everything it relays was decided by
/// the pure functions above; this class only schedules probes, publishes
/// status, and runs the single elevated step when the dialog says yes.
class RemoteFirewallService {
  RemoteFirewallService._();

  static final RemoteFirewallService instance = RemoteFirewallService._();

  /// What the UI renders. Published by [recheck] and [fix]; never mutated
  /// from outside the service.
  final ValueNotifier<RemoteFirewallStatus> status =
      ValueNotifier<RemoteFirewallStatus>(RemoteFirewallStatus.unknown());

  /// True while the elevated step (and its UAC prompt) is in flight — the
  /// dialog shows its busy state off this.
  final ValueNotifier<bool> applying = ValueNotifier<bool>(false);

  /// Test seam: the process runner. Production always hits [_windowsRunner].
  RemoteFirewallRunner runner = _windowsRunner;

  /// Test seam: the exe path rules are checked against.
  String Function() exePathOf = () => Platform.resolvedExecutable;

  /// Test seam: the preferred port (for the fix's port window).
  int Function()? preferredPortOf;

  /// Test seam: the platform gate. The firewall story is Windows-only;
  /// everywhere else the status stays unknown and the 90-second hint —
  /// or nothing at all — is the whole UI.
  bool Function() isWindowsOf = () => Platform.isWindows;

  Future<RemoteFirewallStatus>? _inFlight;
  static const Duration _freshFor = Duration(seconds: 5);
  static const Duration _probeTimeout = Duration(seconds: 20);
  static const Duration _fixTimeout = Duration(minutes: 3);

  /// The port window [fix] writes into the rule. Kept behind a getter so the
  /// dialog's copy and the script can never disagree.
  String get portRange =>
      remoteFirewallPortRange(preferredPortOf?.call() ?? 7258);

  /// Re-checks the rule against the running exe. Called on every remote
  /// start — which means every app launch with Remote enabled and every
  /// toggle-on — and after every fix. Concurrent callers share one probe;
  /// a probe fresher than [_freshFor] is reused unless [force] asks again
  /// (the verify-after-fix).
  Future<RemoteFirewallStatus> recheck({bool force = false}) async {
    if (!isWindowsOf()) {
      status.value = RemoteFirewallStatus.unknown();
      return status.value;
    }
    final RemoteFirewallStatus current = status.value;
    if (!force &&
        current.checkedAt != null &&
        DateTime.now().difference(current.checkedAt!) < _freshFor) {
      return current;
    }
    final Future<RemoteFirewallStatus>? running = _inFlight;
    if (running != null) return running;
    final Future<RemoteFirewallStatus> probe = _probe();
    _inFlight = probe;
    try {
      final RemoteFirewallStatus next = await probe;
      status.value = next;
      return next;
    } finally {
      if (identical(_inFlight, probe)) _inFlight = null;
    }
  }

  Future<RemoteFirewallStatus> _probe() async {
    try {
      final ProcessResult result = await runner(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          buildFirewallDetectScript(exePathOf()),
        ],
        stdoutEncoding: utf8,
      ).timeout(_probeTimeout);
      final RemoteFirewallProbe? probe =
          parseFirewallReportBody('${result.stdout}');
      if (probe == null) {
        return RemoteFirewallStatus.unknown(detail: 'no readable probe answer');
      }
      if (!probe.ok) {
        debugPrint('[SALU] remote: firewall probe failed: ${probe.error}');
        return RemoteFirewallStatus.unknown(detail: probe.error);
      }
      return evaluateFirewallReport(
        exePath: exePathOf(),
        rules: probe.rules,
        profiles: probe.profiles,
      );
    } catch (error) {
      debugPrint('[SALU] remote: firewall probe error: $error');
      return RemoteFirewallStatus.unknown(detail: '$error');
    }
  }

  /// One press of the dialog's Allow button: UAC → the elevated fix → a
  /// forced re-check so the status line tells the truth afterwards.
  Future<RemoteFirewallFixResult> fix({required bool makePrivate}) async {
    if (!isWindowsOf()) {
      return const RemoteFirewallFixResult(RemoteFirewallFixOutcome.failed,
          detail: 'not Windows');
    }
    if (applying.value) {
      return const RemoteFirewallFixResult(RemoteFirewallFixOutcome.cancelled);
    }
    applying.value = true;
    try {
      final String script = buildFirewallFixScript(
        exePath: exePathOf(),
        portRange: portRange,
        makePrivate: makePrivate,
      );
      final String encoded = encodePsCommand(script);
      // The one UAC moment. The elevated child is a headless PowerShell:
      // -WindowStyle travels in its own argument list (an outer
      // -WindowStyle on Start-Process is a known UAC-fragile combination).
      final ProcessResult result = await runner(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          '\$p=Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru '
              "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass',"
              "'-WindowStyle','Hidden','-EncodedCommand','$encoded';"
              'exit \$p.ExitCode',
        ],
        stdoutEncoding: utf8,
      ).timeout(_fixTimeout);
      final String output =
          '${result.stdout}\n${result.stderr}'.toLowerCase();
      if (result.exitCode != 0) {
        if (output.contains('cancel')) {
          return const RemoteFirewallFixResult(
              RemoteFirewallFixOutcome.cancelled);
        }
        debugPrint('[SALU] remote: firewall fix failed: $output');
        return RemoteFirewallFixResult(RemoteFirewallFixOutcome.failed,
            detail: output.trim());
      }
      // Verify: re-read the rules NOW — a shared in-flight probe (a just-
      // started toggle-on check) could predate the elevated step, so the
      // verify deliberately bypasses both the freshness window and the
      // dedupe. The dialog only goes green on this answer.
      final RemoteFirewallStatus verified = await _probe();
      status.value = verified;
      if (!verified.needsRuleFix && (!makePrivate || !verified.needsPrivateNetwork)) {
        return const RemoteFirewallFixResult(RemoteFirewallFixOutcome.applied);
      }
      if (verified.ruleState == RemoteFirewallRuleState.unknown) {
        // The rule write succeeded but the verify failed to answer — claim
        // nothing either way; the honest copy is "couldn't confirm".
        return const RemoteFirewallFixResult(RemoteFirewallFixOutcome.failed,
            detail: 'verify failed');
      }
      return const RemoteFirewallFixResult(RemoteFirewallFixOutcome.failed,
          detail: 'rule still not in effect');
    } catch (error) {
      debugPrint('[SALU] remote: firewall fix error: $error');
      return RemoteFirewallFixResult(RemoteFirewallFixOutcome.failed,
          detail: '$error');
    } finally {
      applying.value = false;
    }
  }

  /// The manual fallback (third-party firewalls, group policy) — the same
  /// door the 90-second hint has always opened.
  Future<void> openWindowsFirewallSettings() async {
    if (!Platform.isWindows) return;
    try {
      await Process.start(
        'control',
        <String>['firewall.cpl'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }
}
