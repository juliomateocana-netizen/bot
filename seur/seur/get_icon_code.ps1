$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$js = (Invoke-WebRequest -Uri 'https://web-static.wallapop.com/nextjs/_next/static/chunks/2o3jzkcb1s5sv.js' -Headers $headers -UseBasicParsing).Content
$idx = $js.IndexOf('pro_badge_filled')
if ($idx -ge 0) {
  $start = [math]::Max(0, $idx - 300)
  $len = [math]::Min(1200, $js.Length - $start)
  Write-Host $js.Substring($start, $len)
}
