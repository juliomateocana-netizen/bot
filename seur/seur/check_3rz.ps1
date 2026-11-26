$headers = @{ 'User-Agent' = 'Mozilla/5.0' }
$c = (Invoke-WebRequest -Uri 'https://web-static.wallapop.com/nextjs/_next/static/chunks/3rzb0axam30l4.js' -Headers $headers -UseBasicParsing).Content
$idx = $c.IndexOf('pro_badge_filled')
if ($idx -ge 0) {
  Write-Host "FOUND at: $idx"
  Write-Host $c.Substring([math]::Max(0, $idx - 150), [math]::Min(500, $c.Length - [math]::Max(0, $idx - 150)))
}
