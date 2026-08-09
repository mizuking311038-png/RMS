# Link checks ignoring mailto:, tel:, javascript: schemes and fragments
$root = Get-Location
Write-Output "Root: $root"
$htmlFiles = Get-ChildItem -Recurse -File -Include *.html,*.htm
$external = @(); $relativeMissing = @(); $anchorMissing = @(); $imgMissingAlt = @(); $emptyHref = @(); $h1Missing = @();
foreach ($f in $htmlFiles) {
  $text = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $text) { continue }

  $hrefParts = $text -split 'href='
  for ($i = 1; $i -lt $hrefParts.Count; $i++) {
    $p = $hrefParts[$i].TrimStart()
    if ($p.Length -lt 2) { continue }
    $quote = $p[0]
    if ($quote -ne '"' -and $quote -ne "'") { continue }
    $rest = $p.Substring(1)
    $idx = $rest.IndexOf($quote)
    if ($idx -lt 0) { continue }
    $link = $rest.Substring(0,$idx)
    $clean = $link.Split('?')[0].Split('#')[0]
    # ignore mailto, tel, javascript and fragments
    if ($clean.StartsWith('mailto:') -or $clean.StartsWith('tel:') -or $clean.StartsWith('javascript:') -or $clean.StartsWith('#')) { continue }
    if ($clean -match '^(http:|https:)') { $external += @{file=$f.FullName; link=$link} }
    else { if ($clean.StartsWith('/')) { $target = Join-Path $root ($clean.TrimStart('/')) } else { $target = Join-Path $f.DirectoryName $clean } if (-not (Test-Path $target)) { $tryIndex = Join-Path $target 'index.html'; if (-not (Test-Path $tryIndex)) { $relativeMissing += @{file=$f.FullName; link=$link; target=$target} } } }
  }

  $srcParts = $text -split 'src='
  for ($i = 1; $i -lt $srcParts.Count; $i++) {
    $p = $srcParts[$i].TrimStart()
    if ($p.Length -lt 2) { continue }
    $quote = $p[0]
    if ($quote -ne '"' -and $quote -ne "'") { continue }
    $rest = $p.Substring(1)
    $idx = $rest.IndexOf($quote)
    if ($idx -lt 0) { continue }
    $link = $rest.Substring(0,$idx)
    $clean = $link.Split('?')[0].Split('#')[0]
    if ($clean.StartsWith('mailto:') -or $clean.StartsWith('tel:') -or $clean.StartsWith('javascript:')) { continue }
    if ($clean -match '^(http:|https:)') { $external += @{file=$f.FullName; link=$link} } else { if ($clean.StartsWith('/')) { $target = Join-Path $root ($clean.TrimStart('/')) } else { $target = Join-Path $f.DirectoryName $clean } if (-not (Test-Path $target)) { $tryIndex = Join-Path $target 'index.html'; if (-not (Test-Path $tryIndex)) { $relativeMissing += @{file=$f.FullName; link=$link; target=$target} } } }
  }

  # image alt check
  $pos = 0
  while ($true) {
    $idx = $text.IndexOf('<img', $pos)
    if ($idx -lt 0) { break }
    $end = $text.IndexOf('>', $idx)
    if ($end -lt 0) { break }
    $tag = $text.Substring($idx, $end - $idx + 1)
    if ($tag -notmatch 'alt\s*=') { $imgMissingAlt += @{file=$f.FullName; tag=$tag} }
    $pos = $end + 1
  }

  if ($text -match 'href\s*=\s*"\s*"|href\s*=\s*''\s*''') { $emptyHref += @{file=$f.FullName} }
  if ($text -notmatch '<h1\b') { $h1Missing += $f.FullName }
}

# External checks
$externalResults = @()
if ($external.Count -gt 0) {
  $seen = @{}
  foreach ($e in $external) {
    $url = $e.link
    if ($seen.ContainsKey($url)) { continue }
    $seen[$url] = $true
    try { $code = & curl.exe -I -s -o NUL -w "%{http_code}" $url 2>$null } catch { $code = 'ERR' }
    $externalResults += @{link=$url; status=$code}
  }
}

# Summary
Write-Output "HTML files scanned: $($htmlFiles.Count)"
Write-Output "External links found: $($external.Count)"
Write-Output "Relative/missing link issues: $($relativeMissing.Count)"
Write-Output "Missing anchors: $($anchorMissing.Count)"
Write-Output "Images missing alt: $($imgMissingAlt.Count)"
Write-Output "Empty href anchors: $($emptyHref.Count)"
Write-Output "Files missing <h1>: $($h1Missing.Count)"

if ($relativeMissing.Count -gt 0) { Write-Output "\n-- Relative missing samples --"; $relativeMissing | Select-Object -First 50 | ForEach-Object { Write-Output ("File: {0} -> link: {1} -> expected path: {2}" -f $_.file,$_.link,$_.target) } }
if ($emptyHref.Count -gt 0) { Write-Output "\n-- Empty href samples --"; $emptyHref | Select-Object -First 50 | ForEach-Object { Write-Output ("File: {0}" -f $_.file) } }
if ($externalResults.Count -gt 0) { Write-Output "\n-- External link status samples --"; $externalResults | Select-Object -First 50 | ForEach-Object { Write-Output ("{0} -> {1}" -f $_.link,$_.status) } }

# Save report
$reportDir = Join-Path $root 'link-check-report'
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
$relativeMissing | ConvertTo-Json -Depth 5 | Out-File (Join-Path $reportDir 'relativeMissing_ignoremailto.json')
$externalResults | ConvertTo-Json -Depth 5 | Out-File (Join-Path $reportDir 'externalResults_ignoremailto.json')
Write-Output "Full JSON reports written to: $reportDir"