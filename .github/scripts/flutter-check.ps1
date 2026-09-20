# Keep actionable failure output in the check annotations as well as the logs.
# This also makes diagnostics available to clients that cannot download the
# signed Azure log archive returned by GitHub's log API.
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArguments
)

$lines = [System.Collections.Generic.List[string]]::new()
& flutter @FlutterArguments 2>&1 | ForEach-Object {
  $line = $_.ToString()
  $lines.Add($line)
  Write-Host $line
}
$code = $LASTEXITCODE
if ($code -ne 0) {
  $failures = $lines | Select-String -Pattern '\[E\]|EXCEPTION|Error:|error -|warning -|Expected:|Actual:|Test failed' -Context 2,12
  $summary = (($failures | ForEach-Object { $_.ToString() }) -join "`n")
  $summary += "`n--- Output tail ---`n" + (($lines | Select-Object -Last 100) -join "`n")
  if ($summary.Length -gt 60000) { $summary = $summary.Substring(0, 60000) }
  $escaped = $summary.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
  Write-Host "::error title=Flutter validation failed::$escaped"
}
exit $code
