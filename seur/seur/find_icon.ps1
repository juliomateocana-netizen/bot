$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$r = Invoke-WebRequest -Uri 'https://es.wallapop.com/item/iphone-18-pro-max-256gb-rojo-1328148363' -Headers $headers -UseBasicParsing
$scripts = [regex]::Matches($r.Content, 'src="(https://[^"]+/_next/static/[^"]+\.js)"')
Write-Host "Scripts count: $($scripts.Count)"
foreach ($s in $scripts) {
  try {
    $jsUrl = $s.Groups[1].Value
    $js = (Invoke-WebRequest -Uri $jsUrl -Headers $headers -UseBasicParsing).Content
    if ($js -like '*pro_badge_filled*') {
      Write-Host "FOUND in: $jsUrl"
      $matchesM = [regex]::Matches($js, '.{0,100}pro_badge_filled.{0,600}')
      foreach ($m in $matchesM) {
        Write-Host "PATH SNIPPET: $($m.Value)"
      }
      break
    }
  } catch {}
}
