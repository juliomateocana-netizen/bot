$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$r = Invoke-WebRequest -Uri 'https://es.wallapop.com/item/iphone-18-pro-max-256gb-rojo-1328148363' -Headers $headers -UseBasicParsing
$scripts = [regex]::Matches($r.Content, 'src="(https://[^"]+/_next/static/[^"]+\.js)"')
foreach ($s in $scripts) {
  try {
    $jsUrl = $s.Groups[1].Value
    $js = (Invoke-WebRequest -Uri $jsUrl -Headers $headers -UseBasicParsing).Content
    if ($js -like '*pro_badge_filled*') {
      $matchesM = [regex]::Matches($js, 'pro_badge_filled["'':\s]+([^}]+)')
      foreach ($m in $matchesM) {
        Write-Host "FOUND MAPPING in $jsUrl :"
        Write-Host $m.Value.Substring(0, [math]::Min(500, $m.Value.Length))
      }
    }
  } catch {}
}
