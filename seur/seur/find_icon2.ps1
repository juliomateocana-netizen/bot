$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$r = Invoke-WebRequest -Uri 'https://es.wallapop.com/item/iphone-18-pro-max-256gb-rojo-1328148363' -Headers $headers -UseBasicParsing
$scripts = [regex]::Matches($r.Content, 'src="(https://[^"]+/_next/static/[^"]+\.js)"')
foreach ($s in $scripts) {
  try {
    $jsUrl = $s.Groups[1].Value
    $js = (Invoke-WebRequest -Uri $jsUrl -Headers $headers -UseBasicParsing).Content
    $idx = $js.IndexOf('pro_badge_filled')
    if ($idx -ge 0) {
      Write-Host "Found in $jsUrl at $idx"
      $start = [math]::Max(0, $idx - 200)
      $len = [math]::Min(800, $js.Length - $start)
      Write-Host $js.Substring($start, $len)
      break
    }
  } catch {}
}
