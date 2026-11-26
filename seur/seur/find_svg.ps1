$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$r = Invoke-WebRequest -Uri 'https://es.wallapop.com/item/iphone-18-pro-max-256gb-rojo-1328148363' -Headers $headers -UseBasicParsing
$scripts = [regex]::Matches($r.Content, 'src="(https://[^"]+/_next/static/[^"]+\.js)"')
foreach ($s in $scripts) {
  try {
    $jsUrl = $s.Groups[1].Value
    $js = (Invoke-WebRequest -Uri $jsUrl -Headers $headers -UseBasicParsing).Content
    if ($js -like '*pro_badge*') {
      $matchesM = [regex]::Matches($js, '(<svg[^>]*>.*?</svg>)|([a-zA-Z0-9_]+:\s*\{[^}]*viewBox[^}]*\})')
      foreach ($m in $matchesM) {
        if ($m.Value -like '*badge*' -or $m.Value -like '*check*') {
          Write-Host "SVG:" $m.Value
        }
      }
      # Search for path data
      $paths = [regex]::Matches($js, 'd:"([^"]+)"')
      foreach ($p in $paths) {
        if ($p.Value -like '*M*' -and $p.Value.Length -gt 100 -and $p.Value.Length -lt 400) {
          # Write-Host "Path: $($p.Groups[1].Value)"
        }
      }
    }
  } catch {}
}
