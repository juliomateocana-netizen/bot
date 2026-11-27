require('dotenv').config();

// Dominio base con las dos 'a' (U+0430) y la 'o' (U+043E) en cirilico
// w\u0430ll\u0430p\u043Ep.com
const DEFAULT_DOMAIN = 'wаllаpоp.com';
const DEFAULT_BASE_URL = `https://${DEFAULT_DOMAIN}`;

const port = parseInt(process.env.PORT || '3000', 10);
const redirectCode = parseInt(process.env.REDIRECT_CODE || '302', 10) === 301 ? 301 : 302;

let publicBaseUrl = (process.env.PUBLIC_BASE_URL || DEFAULT_BASE_URL).trim();
// Quitar barra final si estuviera presente
if (publicBaseUrl.endsWith('/')) {
  publicBaseUrl = publicBaseUrl.slice(0, -1);
}

module.exports = {
  port,
  redirectCode,
  publicBaseUrl,
  domain: DEFAULT_DOMAIN
};
