# Keep actionable diagnostics in check annotations as well as the build logs.
# Each annotation stays below GitHub's 4 KiB truncation limit, so the failed
# test names and details remain available without downloading the log archive.
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArguments
)

function Write-Annotation([string] $level, [string] $title, [string] $message) {
  $escaped = $message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
  Write-Host "::$level title=$title::$escaped"
}

$lines = [System.Collections.Generic.List[string]]::new()
& flutter @FlutterArguments 2>&1 | ForEach-Object {
  $line = $_.ToString()
  $lines.Add($line)
  Write-Host $line
}
$code = $LASTEXITCODE
if ($code -ne 0) {
  $failedTests = ($lines | Where-Object { $_ -match '\[E\]' }) -join "`n"
  if ($failedTests) {
    Write-Annotation 'error' 'Failed tests' $failedTests.Substring(0, [Math]::Min(3500, $failedTests.Length))
  }
  $matches = $lines | Select-String -Pattern '\[E\]|EXCEPTION|Error:|error -|warning -|Expected:|Actual:|Test failed' -Context 2,12
  $summary = (($matches | ForEach-Object { $_.ToString() }) -join "`n")
  $summary += "`n--- Output tail ---`n" + (($lines | Select-Object -Last 60) -join "`n")
  for ($i = 0; $i -lt [Math]::Min(21000, $summary.Length); $i += 3000) {
    $part = $summary.Substring($i, [Math]::Min(3000, $summary.Length - $i))
    Write-Annotation 'error' "Flutter diagnostics $([int]($i / 3000) + 1)" $part
  }
} else {
  $result = (($lines | Select-Object -Last 3) -join "`n").Trim()
  Write-Annotation 'notice' "Flutter $($FlutterArguments[0]) succeeded" $result
}
exit $code
