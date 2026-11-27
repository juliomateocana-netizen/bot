const { escapeHtml, formatDate } = require('./utils');

/**
 * Plantilla de estilos CSS compartidos con soporte para tema claro y oscuro
 * Sin dependencias externas ni CDN. Sin emojis.
 */
function getSharedStyles() {
  return `
    :root {
      --bg: #F7FAFA;
      --card-bg: #FFFFFF;
      --border: #DDE5E8;
      --text: #222B30;
      --text-muted: #5E717D;
      --primary: #028070;
      --primary-hover: #016357;
      --primary-light: #E6F6F4;
      --danger: #C5221F;
      --danger-hover: #A01B18;
      --danger-light: #FCE8E6;
      --code-bg: #F0F4F6;
      --radius: 8px;
      --shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
      --font: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #11181D;
        --card-bg: #1A2328;
        --border: #2D3A42;
        --text: #EDF2F4;
        --text-muted: #8E9FA8;
        --primary: #14B8A6;
        --primary-hover: #2DD4BF;
        --primary-light: #132E2F;
        --danger: #F87171;
        --danger-hover: #EF4444;
        --danger-light: #361A1C;
        --code-bg: #222E35;
        --shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
      }
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: var(--font);
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 24px 16px;
      min-height: 100vh;
    }

    .container {
      max-width: 980px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 20px;
    }

    header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      border-bottom: 1px solid var(--border);
      padding-bottom: 12px;
    }

    .logo-title {
      font-size: 20px;
      font-weight: 700;
      letter-spacing: -0.5px;
      color: var(--primary);
    }

    .logo-sub {
      font-size: 13px;
      color: var(--text-muted);
      margin-left: 8px;
      font-weight: 500;
    }

    .card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 20px;
      box-shadow: var(--shadow);
    }

    .card-title {
      font-size: 16px;
      font-weight: 600;
      margin-bottom: 14px;
    }

    .form-grid {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 12px;
      align-items: end;
    }

    @media (max-width: 640px) {
      .form-grid { grid-template-columns: 1fr; }
    }

    .form-group {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    .form-row {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 12px;
    }

    @media (max-width: 640px) {
      .form-row { grid-template-columns: 1fr; }
    }

    label {
      font-size: 13px;
      font-weight: 600;
      color: var(--text);
    }

    input[type="text"] {
      font-family: inherit;
      font-size: 14px;
      color: var(--text);
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 9px 12px;
      outline: none;
      transition: border-color 0.15s ease;
      width: 100%;
    }

    input[type="text"]:focus {
      border-color: var(--primary);
    }

    .btn {
      font-family: inherit;
      font-size: 13px;
      font-weight: 600;
      padding: 9px 16px;
      border-radius: var(--radius);
      border: 1px solid transparent;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      text-decoration: none;
      transition: background-color 0.15s ease, border-color 0.15s ease, transform 0.05s;
      white-space: nowrap;
    }

    .btn:active { transform: scale(0.99); }

    .btn-primary {
      background: var(--primary);
      color: #FFFFFF;
      border-color: var(--primary);
    }

    .btn-primary:hover {
      background: var(--primary-hover);
      border-color: var(--primary-hover);
    }

    .btn-secondary {
      background: var(--code-bg);
      color: var(--text);
      border-color: var(--border);
    }

    .btn-secondary:hover {
      background: var(--border);
    }

    .btn-danger {
      background: var(--danger-light);
      color: var(--danger);
      border-color: transparent;
    }

    .btn-danger:hover {
      background: var(--danger);
      color: #FFFFFF;
    }

    .btn-sm {
      padding: 5px 10px;
      font-size: 12px;
    }

    /* Caja de resultado de enlace generado */
    .result-box {
      margin-top: 16px;
      padding: 16px;
      background: var(--primary-light);
      border: 1px solid var(--primary);
      border-radius: var(--radius);
      display: none;
      flex-direction: column;
      gap: 12px;
    }

    .result-box.active {
      display: flex;
    }

    .result-header {
      font-size: 13px;
      font-weight: 600;
      color: var(--text);
    }

    .result-content {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      flex-wrap: wrap;
    }

    .result-link {
      font-size: 17px;
      font-weight: 700;
      color: var(--primary);
      word-break: break-all;
    }

    .result-qr {
      width: 130px;
      height: 130px;
      border: 1px solid var(--border);
      border-radius: var(--radius);
      background: #FFFFFF;
      padding: 6px;
      display: block;
    }

    /* Tabla de enlaces */
    .table-wrapper {
      overflow-x: auto;
      margin-top: 8px;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      text-align: left;
    }

    th {
      padding: 10px 12px;
      background: var(--code-bg);
      color: var(--text-muted);
      font-weight: 600;
      border-bottom: 1px solid var(--border);
      white-space: nowrap;
    }

    td {
      padding: 11px 12px;
      border-bottom: 1px solid var(--border);
      vertical-align: middle;
    }

    tr:last-child td { border-bottom: none; }
    tbody tr:hover td { background: var(--code-bg); }

    .link-short {
      font-weight: 600;
      color: var(--primary);
      text-decoration: none;
      word-break: break-all;
    }

    .link-short:hover { text-decoration: underline; }

    .link-dest {
      color: var(--text-muted);
      text-decoration: none;
      max-width: 320px;
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .link-dest:hover { color: var(--text); text-decoration: underline; }

    .badge-clicks {
      display: inline-block;
      padding: 2px 8px;
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 9999px;
      font-weight: 600;
      font-size: 12px;
      color: var(--text);
    }

    .table-actions {
      display: flex;
      gap: 6px;
      align-items: center;
      justify-content: flex-end;
    }

    /* Mensajes de error y estado */
    .alert {
      padding: 10px 14px;
      border-radius: var(--radius);
      font-size: 13px;
      font-weight: 500;
      margin-top: 10px;
      display: none;
    }

    .alert-error {
      background: var(--danger-light);
      color: var(--danger);
      border: 1px solid var(--danger);
      display: block;
    }

    .toast {
      position: fixed;
      bottom: 20px;
      right: 20px;
      background: var(--text);
      color: var(--card-bg);
      padding: 10px 16px;
      border-radius: var(--radius);
      font-size: 13px;
      font-weight: 600;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15);
      opacity: 0;
      transform: translateY(20px);
      transition: all 0.2s ease;
      pointer-events: none;
      z-index: 100;
    }

    .toast.show {
      opacity: 1;
      transform: translateY(0);
    }

    .empty-state {
      padding: 32px 16px;
      text-align: center;
      color: var(--text-muted);
      font-size: 13px;
    }
  `;
}

/**
 * Renderiza la vista principal del Panel (GET /)
 */
function renderPanel(links, publicBaseUrl, domain) {
  const styles = getSharedStyles();

  // Filas iniciales renderizadas en servidor
  let rowsHtml = '';
  if (links.length === 0) {
    rowsHtml = `<tr id="emptyRow"><td colspan="5" class="empty-state">No hay enlaces registrados aun. Crea el primero arriba.</td></tr>`;
  } else {
    links.forEach(l => {
      const shortUrl = `${publicBaseUrl}/${escapeHtml(l.alias)}`;
      const qrUrl = `/${escapeHtml(l.alias)}/qr`;
      rowsHtml += `
        <tr id="row-${l.id}">
          <td>
            <a href="${shortUrl}" target="_blank" class="link-short">${shortUrl}</a>
          </td>
          <td>
            <a href="${escapeHtml(l.destino)}" target="_blank" class="link-dest" title="${escapeHtml(l.destino)}">${escapeHtml(l.destino)}</a>
          </td>
          <td>
            <span class="badge-clicks">${l.clics}</span>
          </td>
          <td style="color:var(--text-muted); white-space:nowrap;">
            ${formatDate(l.ultimo_acceso)}
          </td>
          <td>
            <div class="table-actions">
              <a href="${qrUrl}" target="_blank" class="btn btn-secondary btn-sm" title="Ver codigo QR">QR</a>
              <button type="button" class="btn btn-secondary btn-sm" onclick="copyText('${shortUrl}')">Copiar</button>
              <button type="button" class="btn btn-danger btn-sm" onclick="deleteLink(${l.id})">Borrar</button>
            </div>
          </td>
        </tr>
      `;
    });
  }

  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(domain)} · Panel de enlaces</title>
  <style>${styles}</style>
</head>
<body>
  <div class="container">
    <header>
      <div>
        <span class="logo-title">${escapeHtml(domain)}</span>
        <span class="logo-sub">Gestor de redirecciones</span>
      </div>
      <div style="font-size: 12px; color: var(--text-muted);">
        Base: <code>${escapeHtml(publicBaseUrl)}</code>
      </div>
    </header>

    <!-- Formulario de creacion (Controlado por eventos sin etiqueta <form>) -->
    <div class="card">
      <div class="card-title">Crear nuevo enlace corto</div>

      <div class="form-row">
        <div class="form-group">
          <label for="inputDestino">URL de destino</label>
          <input
            type="text"
            id="inputDestino"
            placeholder="https://es.wallapop.com/item/anuncio-ejemplo-123456"
            autocomplete="off"
            spellcheck="false"
          >
        </div>

        <div class="form-group">
          <label for="inputAlias">Alias personalizado (opcional)</label>
          <input
            type="text"
            id="inputAlias"
            placeholder="aleatorio si se deja vacio"
            autocomplete="off"
            spellcheck="false"
          >
        </div>
      </div>

      <div style="margin-top: 14px; display: flex; justify-content: flex-end;">
        <button type="button" id="btnCrear" class="btn btn-primary" onclick="handleCreateLink()">
          Crear enlace corto
        </button>
      </div>

      <div id="formError" class="alert alert-error" style="display:none;"></div>

      <!-- Tarjeta de enlace generado (Visible tras crear sin recargar) -->
      <div id="resultBox" class="result-box">
        <div class="result-header">Enlace corto generado exitosamente:</div>
        <div class="result-content">
          <div>
            <div id="resultShortUrl" class="result-link"></div>
            <div style="margin-top: 10px; display: flex; gap: 8px;">
              <button type="button" id="btnCopyResult" class="btn btn-secondary btn-sm" onclick="copyCurrentResult()">
                Copiar enlace
              </button>
              <a id="btnOpenResult" href="#" target="_blank" class="btn btn-secondary btn-sm">
                Abrir enlace
              </a>
            </div>
          </div>
          <div>
            <img id="resultQrImg" src="" alt="QR" class="result-qr">
          </div>
        </div>
      </div>
    </div>

    <!-- Tabla con todos los enlaces -->
    <div class="card">
      <div class="card-title">Enlaces registrados</div>
      <div class="table-wrapper">
        <table>
          <thead>
            <tr>
              <th style="width: 28%;">Enlace corto</th>
              <th style="width: 36%;">Destino</th>
              <th style="width: 10%;">Clics</th>
              <th style="width: 14%;">Ultimo acceso</th>
              <th style="width: 12%; text-align: right;">Acciones</th>
            </tr>
          </thead>
          <tbody id="tableBody">
            ${rowsHtml}
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <div id="toast" class="toast">Copiado al portapapeles</div>

  <script>
    const inputDestino = document.getElementById('inputDestino');
    const inputAlias = document.getElementById('inputAlias');
    const btnCrear = document.getElementById('btnCrear');
    const formError = document.getElementById('formError');
    const resultBox = document.getElementById('resultBox');
    const resultShortUrl = document.getElementById('resultShortUrl');
    const btnOpenResult = document.getElementById('btnOpenResult');
    const resultQrImg = document.getElementById('resultQrImg');
    const tableBody = document.getElementById('tableBody');
    const toast = document.getElementById('toast');

    let currentShortUrl = '';

    // Manejar creacion de enlace via API sin recargar
    async function handleCreateLink() {
      formError.style.display = 'none';
      formError.textContent = '';

      const destino = inputDestino.value.trim();
      const alias = inputAlias.value.trim();

      if (!destino) {
        showError('Por favor introduce la URL de destino.');
        inputDestino.focus();
        return;
      }

      if (!/^https?:\\/\\//i.test(destino)) {
        showError('La URL de destino debe comenzar por http:// o https://');
        inputDestino.focus();
        return;
      }

      btnCrear.disabled = true;
      btnCrear.textContent = 'Creando...';

      try {
        const res = await fetch('/api/links', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ destino, alias })
        });

        const data = await res.json();

        if (!res.ok) {
          throw new Error(data.error || 'Error al crear el enlace.');
        }

        // Mostrar resultado
        currentShortUrl = data.shortUrl;
        resultShortUrl.textContent = data.shortUrl;
        btnOpenResult.href = data.shortUrl;
        resultQrImg.src = data.qrUrl + '?t=' + Date.now();
        resultBox.classList.add('active');

        // Limpiar inputs
        inputDestino.value = '';
        inputAlias.value = '';

        // Anadir fila a la tabla dinamicamente
        const emptyRow = document.getElementById('emptyRow');
        if (emptyRow) {
          emptyRow.remove();
        }

        const newRow = document.createElement('tr');
        newRow.id = 'row-' + data.id;
        newRow.innerHTML = \`
          <td>
            <a href="\${escapeHtml(data.shortUrl)}" target="_blank" class="link-short">\${escapeHtml(data.shortUrl)}</a>
          </td>
          <td>
            <a href="\${escapeHtml(data.destino)}" target="_blank" class="link-dest" title="\${escapeHtml(data.destino)}">\${escapeHtml(data.destino)}</a>
          </td>
          <td>
            <span class="badge-clicks">0</span>
          </td>
          <td style="color:var(--text-muted); white-space:nowrap;">-</td>
          <td>
            <div class="table-actions">
              <a href="\${escapeHtml(data.qrUrl)}" target="_blank" class="btn btn-secondary btn-sm" title="Ver codigo QR">QR</a>
              <button type="button" class="btn btn-secondary btn-sm" onclick="copyText('\${escapeHtml(data.shortUrl)}')">Copiar</button>
              <button type="button" class="btn btn-danger btn-sm" onclick="deleteLink(\${data.id})">Borrar</button>
            </div>
          </td>
        \`;

        tableBody.insertBefore(newRow, tableBody.firstChild);
        showToast('Enlace creado exitosamente');
      } catch (err) {
        showError(err.message || 'Error de conexion.');
      } finally {
        btnCrear.disabled = false;
        btnCrear.textContent = 'Crear enlace corto';
      }
    }

    // Borrar enlace
    async function deleteLink(id) {
      if (!confirm('¿Seguro que deseas eliminar este enlace?')) return;

      try {
        const res = await fetch('/api/links/' + id, { method: 'DELETE' });
        const data = await res.json();

        if (!res.ok || !data.success) {
          alert(data.error || 'No se pudo eliminar el enlace.');
          return;
        }

        const row = document.getElementById('row-' + id);
        if (row) {
          row.remove();
        }

        if (tableBody.children.length === 0) {
          tableBody.innerHTML = '<tr id="emptyRow"><td colspan="5" class="empty-state">No hay enlaces registrados aun. Crea el primero arriba.</td></tr>';
        }

        showToast('Enlace eliminado');
      } catch (e) {
        alert('Error al intentar borrar el enlace.');
      }
    }

    function copyCurrentResult() {
      if (currentShortUrl) {
        copyText(currentShortUrl);
      }
    }

    function copyText(text) {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(() => showToast('Copiado al portapapeles')).catch(() => fallbackCopy(text));
      } else {
        fallbackCopy(text);
      }
    }

    function fallbackCopy(text) {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand('copy');
        showToast('Copiado al portapapeles');
      } catch (e) {}
      document.body.removeChild(ta);
    }

    function showError(msg) {
      formError.textContent = msg;
      formError.style.display = 'block';
    }

    function showToast(msg) {
      toast.textContent = msg;
      toast.classList.add('show');
      clearTimeout(window._tTimer);
      window._tTimer = setTimeout(() => toast.classList.remove('show'), 2200);
    }

    function escapeHtml(s) {
      return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
  </script>
</body>
</html>`;
}

/**
 * Renderiza la pagina de error 404 propia con enlace al panel
 */
function render404(alias, domain) {
  const styles = getSharedStyles();
  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>404 · Enlace no encontrado</title>
  <style>
    ${styles}
    .error-card {
      max-width: 460px;
      margin: 80px auto;
      text-align: center;
      padding: 36px 24px;
    }
    .error-code {
      font-size: 54px;
      font-weight: 800;
      color: var(--danger);
      line-height: 1;
      margin-bottom: 12px;
    }
  </style>
</head>
<body>
  <div class="card error-card">
    <div class="error-code">404</div>
    <h1 style="font-size: 18px; font-weight: 700; margin-bottom: 8px;">Enlace no encontrado</h1>
    <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 24px;">
      El enlace solicitado <strong>/${escapeHtml(alias)}</strong> no existe o ha sido eliminado del servicio.
    </p>
    <a href="/" class="btn btn-primary" style="display:inline-flex;">
      Ir al panel de control
    </a>
  </div>
</body>
</html>`;
}

module.exports = {
  renderPanel,
  render404
};
