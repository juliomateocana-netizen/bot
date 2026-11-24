<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Verificación de Servidor PHP</title>
<style>
body { font-family: sans-serif; max-width: 650px; margin: 40px auto; padding: 20px; line-height: 1.6; background: #f9f9f9; color: #333; }
.card { background: #fff; padding: 24px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); }
h1 { color: #13C1AC; margin-top: 0; }
.status-ok { color: #228618; font-weight: bold; }
.status-warn { color: #d97706; font-weight: bold; }
ul { padding-left: 20px; }
li { margin-bottom: 8px; }
.btn { display: inline-block; padding: 10px 18px; background: #13C1AC; color: #fff; text-decoration: none; border-radius: 6px; font-weight: bold; margin-top: 15px; }
</style>
</head>
<body>
<div class="card">
  <h1>✅ Servidor PHP Funcionando Correctamente</h1>
  <p>Si estás viendo esta pantalla, el intérprete PHP de tu hosting está activo y procesando código sin errores 503.</p>

  <h3>Detalles del Entorno:</h3>
  <ul>
    <li><strong>Versión de PHP:</strong> <span class="status-ok"><?= phpversion() ?></span></li>
    <li><strong>Servidor Web:</strong> <?= htmlspecialchars($_SERVER['SERVER_SOFTWARE'] ?? 'Apache/LiteSpeed') ?></li>
    <li><strong>Soporte JSON:</strong> <?= function_exists('json_encode') ? '<span class="status-ok">Activo</span>' : '<span class="status-warn">Falta</span>' ?></li>
    <li><strong>Soporte cURL:</strong> <?= function_exists('curl_init') ? '<span class="status-ok">Activo</span>' : '<span class="status-warn">Fallback activo</span>' ?></li>
    <li><strong>Carpeta data/ escribible:</strong> <?= is_writable(__DIR__ . '/data') ? '<span class="status-ok">Sí</span>' : '<span class="status-warn">Revisar permisos (755/777)</span>' ?></li>
    <li><strong>Carpeta photos/ (Storage imágenes) escribible:</strong> <?= (is_dir(__DIR__ . '/photos') && is_writable(__DIR__ . '/photos')) ? '<span class="status-ok">Sí (Storage activo)</span>' : '<span class="status-warn">Revisar permisos (755/777)</span>' ?></li>
    <li><strong>Archivo products.json:</strong> <?= file_exists(__DIR__ . '/products.json') ? '<span class="status-ok">Presente</span>' : '<span class="status-warn">No encontrado</span>' ?></li>
  </ul>

  <a class="btn" href="index.php">Ir a index.php</a>
  <a class="btn" style="background:#015354;" href="confirmar.php">Ir a confirmar.php</a>
</div>
</body>
</html>
