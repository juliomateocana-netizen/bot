$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$r = Invoke-WebRequest -Uri 'https://es.wallapop.com/item/iphone-18-pro-max-256gb-rojo-1328148363' -Headers $headers -UseBasicParsing
$scripts = [regex]::Matches($r.Content, 'src="(https://[^"]+/_next/static/[^"]+\.js)"')
foreach ($s in $scripts) {
  try {
    $jsUrl = $s.Groups[1].Value
    $js = (Invoke-WebRequest -Uri $jsUrl -Headers $headers -UseBasicParsing).Content
    if ($js -like '*pro_badge_filled*') {
      # Look for template or svg
      $idx = $js.IndexOf('pro_badge_filled')
      $around = $js.Substring([math]::Max(0, $idx - 500), [math]::Min(1500, $js.Length - [math]::Max(0, $idx - 500)))
      Write-Host "FOUND in $jsUrl :"
      Write-Host $around
    }
  } catch {}
}
