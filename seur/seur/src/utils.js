const crypto = require('crypto');

// Alfabeto de 32 caracteres sin simbolos ambiguos (se excluyen 0, o, 1, l para evitar confusiones)
const UNAMBIGUOUS_ALPHABET = '23456789abcdefghijkmnpqrstuvwxyz';

// Rutas reservadas que no pueden usarse como alias
const RESERVED_ALIASES = new Set([
  'api',
  'healthz',
  'panel',
  'favicon',
  'favicon.ico',
  'public',
  'static',
  'assets',
  'qr',
  'admin',
  'robots.txt',
  'sitemap.xml'
]);

/**
 * Genera un alias criptograficamente seguro sin caracteres ambiguos
 */
function generateRandomAlias(length = 6) {
  let result = '';
  const alphabetLength = UNAMBIGUOUS_ALPHABET.length;
  for (let i = 0; i < length; i++) {
    const randomIndex = crypto.randomInt(0, alphabetLength);
    result += UNAMBIGUOUS_ALPHABET[randomIndex];
  }
  return result;
}

/**
 * Limpia y normaliza el alias:
 * - Solo admite minusculas, numeros y guiones
 * - Maximo 32 caracteres
 */
function cleanAlias(alias) {
  if (typeof alias !== 'string') return '';
  return alias
    .trim()
    .toLowerCase()
    .replace(/[\/\s\\_]+/g, '-')      // Espacios y barras a guiones
    .replace(/[^a-z0-9-]/g, '')       // Eliminar caracteres no permitidos
    .replace(/-+/g, '-')              // Colapsar guiones consecutivos
    .replace(/^-+|-+$/g, '')          // Recortar guiones extremos
    .slice(0, 32);                    // Limite maximo de 32 caracteres
}

/**
 * Comprueba si el alias coincide con una ruta propia o reservada
 */
function isReservedAlias(alias) {
  if (!alias) return true;
  return RESERVED_ALIASES.has(alias.toLowerCase());
}

/**
 * Valida la URL de destino protegiendo contra esquemas peligrosos
 * Solo permite protocolos http:// y https://
 */
function isValidDestination(urlStr) {
  if (typeof urlStr !== 'string') return false;
  const trimmed = urlStr.trim();
  if (!trimmed) return false;

  // Comprobar inicio estricto
  if (!/^https?:\/\//i.test(trimmed)) {
    return false;
  }

  try {
    const parsed = new URL(trimmed);
    // Protocolo exclusivamente http: o https:
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return false;
    }
    // Debe tener hostname valido
    if (!parsed.hostname || parsed.hostname.length < 1) {
      return false;
    }
    return true;
  } catch (e) {
    return false;
  }
}

/**
 * Escapar texto para renderizado seguro en HTML
 */
function escapeHtml(text) {
  if (text == null) return '';
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

/**
 * Formatear fecha para la interfaz
 */
function formatDate(dateStr) {
  if (!dateStr) return '-';
  try {
    const d = new Date(dateStr.endsWith('Z') ? dateStr : dateStr + 'Z');
    if (isNaN(d.getTime())) return dateStr;
    return d.toLocaleString('es-ES', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  } catch (e) {
    return dateStr;
  }
}

module.exports = {
  UNAMBIGUOUS_ALPHABET,
  generateRandomAlias,
  cleanAlias,
  isReservedAlias,
  isValidDestination,
  escapeHtml,
  formatDate
};
