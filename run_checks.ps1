# Simple link/HTML/accessibility checks for static HTML site
$root = Get-Location
Write-Output "Root: $root"
$htmlFiles = Get-ChildItem -Recurse -File -Include *.html,*.htm
$external = @(); $relativeMissing = @(); $anchorMissing = @(); $imgMissingAlt = @(); $emptyHref = @(); $h1Missing = @();
foreach ($f in $htmlFiles) {
  $text = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $text) { continue }
  
  # naive href parsing
  $hrefParts = $text -split 'href='
  for ($i = 1; $i -lt $hrefParts.Count; $i++) {
    $p = $hrefParts[$i]
    $p = $p.TrimStart()
    if ($p.Length -lt 2) { continue }
    $q = $p[0]
    if ($q -ne '"' -and $q -ne "'") { continue }
    $rest = $p.Substring(1)
    $idx = $rest.IndexOf($q)
    if ($idx -lt 0) { continue }
    $link = $rest.Substring(0,$idx)
    $clean = $link.Split('?')[0].Split('#')[0]
    if ($clean -match '^(http:|https:)') { $external += @{file=$f.FullName; link=$link} }
    elseif ($clean -match '^#') { $anchor = $clean.Substring(1); if (-not ($text -match "(id|name)\s*=\s*['\"]$anchor['\"]")) { $anchorMissing += @{file=$f.FullName; anchor=$anchor}} }
    else { if ($clean -match '^/') { $target = Join-Path $root ($clean.TrimStart('/')) } else { $target = Join-Path $f.DirectoryName $clean } if (-not (Test-Path $target)) { $tryIndex = Join-Path $target 'index.html'; if (-not (Test-Path $tryIndex)) { $relativeMissing += @{file=$f.FullName; link=$link; target=$target} } } }
  }

  # naive src parsing (for images etc.)
  $srcParts = $text -split 'src='
  for ($i = 1; $i -lt $srcParts.Count; $i++) {
    $p = $srcParts[$i]; $p = $p.TrimStart(); if ($p.Length -lt 2) { continue }
    $q = $p[0]; if ($q -ne '"' -and $q -ne "'") { continue }
    $rest = $p.Substring(1); $idx = $rest.IndexOf($q); if ($idx -lt 0) { continue }
    $link = $rest.Substring(0,$idx); $clean = $link.Split('?')[0].Split('#')[0]; if ($clean -match '^(http:|https:)') { $external += @{file=$f.FullName; link=$link} } else { if ($clean -match '^/') { $target = Join-Path $root ($clean.TrimStart('/')) } else { $target = Join-Path $f.DirectoryName $clean } if (-not (Test-Path $target)) { $tryIndex = Join-Path $target 'index.html'; if (-not (Test-Path $tryIndex)) { $relativeMissing += @{file=$f.FullName; link=$link; target=$target} } } }
  }

  # images missing alt via simple check
  if ($text -match '<img') {
    $imgBlocks = ($text -split '<img') | Where-Object { $_ -ne '' }
    foreach ($b in $imgBlocks) { $tag = '<img' + ($b.Split('>')[0]) + '>'; if ($tag -notmatch 'alt\s*=') { $imgMissingAlt += @{file=$f.FullName; tag=$tag} } }
  }

  # empty href
  if ($text -match 'href\s*=\s*"\s*"|href\s*=\s*\'\s*\'') { $emptyHref += @{file=$f.FullName} }

  # H1 check
  if ($text -notmatch '<h1\b') { $h1Missing += $f.FullName }
}

# External checks with curl.exe
$externalResults = @(); if ($external.Count -gt 0) { $seen = @{}; foreach ($e in $external) { $url = $e.link; if ($seen.ContainsKey($url)) { continue } $seen[$url]=1; try { $code = & curl.exe -I -s -o NUL -w "%{http_code}" $url 2>$null } catch { $code = 'ERR' } $externalResults += @{link=$url; status=$code} } }

# Summary
Write-Output "HTML files scanned: $($htmlFiles.Count)"
Write-Output "External links found: $($external.Count)"
Write-Output "Relative/missing link issues: $($relativeMissing.Count)"
Write-Output "Missing anchors: $($anchorMissing.Count)"
Write-Output "Images missing alt: $($imgMissingAlt.Count)"
Write-Output "Empty href anchors: $($emptyHref.Count)"
Write-Output "Files missing <h1>: $($h1Missing.Count)"

if ($relativeMissing.Count -gt 0) { Write-Output "\n-- Relative missing samples --"; $relativeMissing | Select-Object -First 50 | ForEach-Object { Write-Output ("File: {0} -> link: {1} -> expected path: {2}" -f $_.file,$_.link,$_.target) } }
if ($anchorMissing.Count -gt 0) { Write-Output "\n-- Missing anchors samples --"; $anchorMissing | Select-Object -First 50 | ForEach-Object { Write-Output ("File: {0} -> anchor: #{1}" -f $_.file,$_.anchor) } }
if ($imgMissingAlt.Count -gt 0) { Write-Output "\n-- Images missing alt samples --"; $imgMissingAlt | Select-Object -First 50 | ForEach-Object { Write-Output ("File: {0} -> tag: {1}" -f $_.file,$_.tag) } }
if ($emptyHref.Count -gt 0) { Write-Output "\n-- Empty href samples --"; $emptyHref | Select-Object -First 50 | ForEach-Object { Write-Output ("File: {0}" -f $_.file) } }
if ($h1Missing.Count -gt 0) { Write-Output "\n-- Files missing H1 --"; $h1Missing | Select-Object -First 50 | ForEach-Object { Write-Output $_ } }
if ($externalResults.Count -gt 0) { Write-Output "\n-- External link status samples --"; $externalResults | Select-Object -First 50 | ForEach-Object { Write-Output ("{0} -> {1}" -f $_.link,$_.status) } }

# Save report
$reportDir = Join-Path $root 'link-check-report'; if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
$relativeMissing | ConvertTo-Json -Depth 5 | Out-File (Join-Path $reportDir 'relativeMissing.json')
$anchorMissing | ConvertTo-Json -Depth 5 | Out-File (Join-Path $reportDir 'anchorMissing.json')
$imgMissingAlt | ConvertTo-Json -Depth 5 | Out-File (Join-Path $reportDir 'imgMissingAlt.json')
$externalResults | ConvertTo-Json -Depth 5 | Out-File (Join-Path $reportDir 'externalResults.json')
Write-Output "Full JSON reports written to: $reportDir"
