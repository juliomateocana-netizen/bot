const express = require('express');
const QRCode = require('qrcode');
const config = require('./config');
const db = require('./db');
const {
  cleanAlias,
  generateRandomAlias,
  isReservedAlias,
  isValidDestination
} = require('./utils');
const { renderPanel, render404 } = require('./views');

const app = express();

// Desactivar cabecera innecesaria
app.disable('x-powered-by');

// Middlewares para parseo de peticiones
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

/**
 * GET /healthz
 * Comprobacion de salud: responde 200 con texto plano
 */
app.get('/healthz', (req, res) => {
  res.type('text/plain').status(200).send('ok');
});

/**
 * GET /
 * Panel de administracion renderizado en servidor
 */
app.get('/', (req, res) => {
  try {
    const links = db.listAll();
    const html = renderPanel(links, config.publicBaseUrl, config.domain);
    res.type('text/html; charset=utf-8').send(html);
  } catch (err) {
    console.error('Error al renderizar el panel:', err);
    res.status(500).type('text/plain').send('Error interno del servidor.');
  }
});

/**
 * POST /api/links
 * Crea un nuevo enlace corto
 */
app.post('/api/links', (req, res) => {
  try {
    const { destino, alias: customAlias } = req.body || {};

    // Validacion de la URL de destino
    if (!destino || typeof destino !== 'string') {
      return res.status(400).json({ error: 'La URL de destino es obligatoria.' });
    }

    const trimmedDest = destino.trim();
    if (!isValidDestination(trimmedDest)) {
      return res.status(400).json({
        error: 'La URL de destino debe ser valida y comenzar por http:// o https://'
      });
    }

    let finalAlias = '';

    // Si el usuario proporciono un alias personalizado
    if (customAlias && typeof customAlias === 'string' && customAlias.trim().length > 0) {
      finalAlias = cleanAlias(customAlias);

      if (!finalAlias || finalAlias.length < 1) {
        return res.status(400).json({
          error: 'El alias personalizado contiene caracteres no permitidos.'
        });
      }

      if (isReservedAlias(finalAlias)) {
        return res.status(400).json({
          error: `El alias "${finalAlias}" es una palabra reservada del sistema.`
        });
      }

      // Comprobar si ya existe
      const existing = db.findByAlias(finalAlias);
      if (existing) {
        return res.status(409).json({
          error: `El alias "${finalAlias}" ya se encuentra en uso.`
        });
      }
    } else {
      // Generacion automatica con reintento si colisiona
      let attempts = 0;
      const MAX_ATTEMPTS = 15;
      while (attempts < MAX_ATTEMPTS) {
        const candidate = generateRandomAlias(6);
        if (!isReservedAlias(candidate) && !db.findByAlias(candidate)) {
          finalAlias = candidate;
          break;
        }
        attempts++;
      }

      if (!finalAlias) {
        return res.status(500).json({
          error: 'No se pudo generar un alias unico disponible. Intentalo de nuevo.'
        });
      }
    }

    // Insertar en la base de datos
    const newId = db.insertLink(finalAlias, trimmedDest);
    const shortUrl = `${config.publicBaseUrl}/${finalAlias}`;
    const qrUrl = `/${finalAlias}/qr`;

    return res.status(201).json({
      success: true,
      id: newId,
      alias: finalAlias,
      destino: trimmedDest,
      shortUrl,
      qrUrl
    });
  } catch (err) {
    console.error('Error al crear enlace:', err);
    return res.status(500).json({ error: 'Error interno al registrar el enlace.' });
  }
});

/**
 * DELETE /api/links/:id
 * Elimina un enlace por su ID
 */
app.delete('/api/links/:id', (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id) || id <= 0) {
      return res.status(400).json({ error: 'Identificador de enlace no valido.' });
    }

    const deleted = db.deleteById(id);
    if (!deleted) {
      return res.status(404).json({ error: 'El enlace especificado no existe.' });
    }

    return res.json({ success: true });
  } catch (err) {
    console.error('Error al borrar enlace:', err);
    return res.status(500).json({ error: 'Error interno al eliminar el enlace.' });
  }
});

/**
 * GET /:alias/qr
 * Devuelve un PNG del QR del enlace corto
 */
app.get('/:alias/qr', async (req, res) => {
  try {
    const alias = cleanAlias(req.params.alias);
    if (!alias) {
      return res.status(404).type('text/plain').send('Enlace no encontrado.');
    }

    const link = db.findByAlias(alias);
    if (!link) {
      return res.status(404).type('text/plain').send('Enlace no encontrado.');
    }

    // Los enlaces se construyen siempre a partir de PUBLIC_BASE_URL
    const shortUrl = `${config.publicBaseUrl}/${alias}`;

    const pngBuffer = await QRCode.toBuffer(shortUrl, {
      type: 'png',
      width: 320,
      margin: 2,
      color: {
        dark: '#015354',
        light: '#FFFFFF'
      }
    });

    res.type('image/png');
    res.set('Cache-Control', 'public, max-age=86400');
    return res.send(pngBuffer);
  } catch (err) {
    console.error('Error al generar QR:', err);
    return res.status(500).type('text/plain').send('Error al generar el codigo QR.');
  }
});

/**
 * GET /:alias
 * Redirige al destino original, sumando un clic y actualizando ultimo_acceso.
 * Si no existe, muestra pagina 404 propia con enlace al panel.
 */
app.get('/:alias', (req, res) => {
  try {
    const rawAlias = req.params.alias;
    const alias = cleanAlias(rawAlias);

    if (!alias || isReservedAlias(alias)) {
      return res.status(404).type('text/html; charset=utf-8').send(render404(rawAlias, config.domain));
    }

    const link = db.findByAlias(alias);

    if (!link) {
      return res.status(404).type('text/html; charset=utf-8').send(render404(alias, config.domain));
    }

    // Registrar clic y marca de tiempo
    db.recordClick(alias);

    // Responder con el codigo configurado (302 o 301) y cabecera Location
    res.set('Location', link.destino);
    return res.status(config.redirectCode).end();
  } catch (err) {
    console.error('Error en redireccion:', err);
    return res.status(500).type('text/plain').send('Error interno durante la redireccion.');
  }
});

// Manejo general de rutas no coincidentes
app.use((req, res) => {
  res.status(404).type('text/html; charset=utf-8').send(render404(req.path.replace(/^\//, ''), config.domain));
});

// Iniciar servidor
app.listen(config.port, () => {
  console.log(`Servidor activo en el puerto ${config.port}`);
  console.log(`PUBLIC_BASE_URL: ${config.publicBaseUrl}`);
  console.log(`Codigo de redireccion: ${config.redirectCode}`);
});

module.exports = app;
