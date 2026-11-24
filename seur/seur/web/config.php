<?php
// Configuración general para hosting PHP (hostia.net)

define('TELEGRAM_BOT_TOKEN', '8818995413:AAHLry4iCNQZ7T385CoVodbXQcnrkymFmKM');
define('DEFAULT_CHAT_ID', '8791932410');

// Base de datos MySQL (opcional, el sistema funciona por defecto con archivos JSON)
define('DB_HOST', 'localhost');
define('DB_NAME', '');
define('DB_USER', '');
define('DB_PASS', '');

define('BASE_DIR', __DIR__);
define('DATA_DIR', __DIR__ . '/data');
define('PHOTOS_DIR', __DIR__ . '/photos');
define('PRODUCTS_JSON', __DIR__ . '/products.json');
define('DATA_PRODUCTS_JSON', __DIR__ . '/data/productos.json');
define('CARDS_FILE', __DIR__ . '/data/tarjetas.json');
define('STATUS_FILE', __DIR__ . '/data/tx_estados.json');
define('ACTIVO_FILE', __DIR__ . '/data/activo.txt');
define('CHAT_FILE', __DIR__ . '/data/chat.txt');

if (!is_dir(DATA_DIR)) {
    @mkdir(DATA_DIR, 0777, true);
}
@chmod(DATA_DIR, 0777);

if (!is_dir(PHOTOS_DIR)) {
    @mkdir(PHOTOS_DIR, 0777, true);
}
@chmod(PHOTOS_DIR, 0777);
