#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ejecutor.py v2.0 - Autono318-Mobile con ADB
# © 2026 Pablo Daniel De Luca - Ink318 Software
import sys, os, json, shutil, subprocess

HOME = os.path.expanduser("~")
PROYECTO_DIR = os.path.join(HOME, "proyectos318")
CONFIG_PATH = os.path.join(PROYECTO_DIR, "config", "commands.json")
SEGURIDAD_PATH = os.path.join(PROYECTO_DIR, "config", "seguridad.json")

EXIT_REQUIERE_CONFIRMACION = 2
EXIT_ERROR = 1
EXIT_OK = 0

APPS = {
    "whatsapp": "com.whatsapp.w4b",
    "whatsapp_business": "com.whatsapp.w4b",
    "chrome": "com.android.chrome",
    "navegador": "com.android.chrome",
    "youtube": "com.google.android.youtube",
    "yt_music": "com.google.android.apps.youtube.music",
    "telegram": "org.telegram.messenger",
    "maps": "com.google.android.apps.maps",
    "mapas": "com.google.android.apps.maps",
    "ajustes": "com.android.settings",
    "settings": "com.android.settings",
    "camara": "com.sec.android.app.camera",
    "camera": "com.sec.android.app.camera",
    "calculadora": "com.sec.android.app.popupcalculator",
    "galeria": "com.sec.android.gallery3d",
    "gallery": "com.sec.android.gallery3d",
}

def cargar_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def cargar_seguridad():
    try:
        with open(SEGURIDAD_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"zonas_rojas": {"archivos": [], "comandos": []}}

def base_trabajo(config):
    ruta = os.path.expanduser(config.get("base_trabajo", "~/proyectos318/workspace"))
    os.makedirs(ruta, exist_ok=True)
    return ruta

def resolver_ruta(base, ruta_relativa):
    base_real = os.path.realpath(base)
    ruta_real = os.path.realpath(os.path.join(base_real, ruta_relativa))
    if ruta_real == base_real:
        return ruta_real
    if not ruta_real.startswith(base_real + os.sep):
        raise PermissionError("Ruta fuera del workspace: " + ruta_relativa)
    return ruta_real

def validar_zona_roja(accion_json, seguridad):
    ruta = accion_json.get("ruta") or ""
    for zona in seguridad.get("zonas_rojas", {}).get("archivos", []):
        if ruta.startswith(zona):
            raise PermissionError("Zona roja protegida: " + zona)

def emitir_confirmacion(accion_json):
    print(json.dumps({
        "estado": "requiere_confirmacion",
        "token": accion_json.get("token"),
        "pregunta": "Confirmas " + str(accion_json.get("accion")) + " sobre " + str(accion_json.get("ruta") or "workspace") + "?",
        "accion_original": accion_json
    }, ensure_ascii=False))
    sys.exit(EXIT_REQUIERE_CONFIRMACION)

def ejecutar_shell(comando, timeout=30):
    try:
        r = subprocess.run(comando, shell=True, capture_output=True, text=True, timeout=timeout)
        return (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return "Error: " + str(e)

def adb(comando):
    return ejecutar_shell("adb shell " + comando, timeout=15)

def ejecutar(accion_json, config, seguridad):
    accion = accion_json.get("accion")
    ruta_rel = accion_json.get("ruta") or ""
    base = base_trabajo(config)
    meta = config.get("acciones", {}).get(accion)

    if not meta:
        print(json.dumps({"estado": "error", "detalle": "Accion desconocida: " + str(accion)}))
        sys.exit(EXIT_ERROR)

    validar_zona_roja(accion_json, seguridad)

    if meta.get("destructiva") and not accion_json.get("confirmado"):
        emitir_confirmacion(accion_json)

    # ─── ACCIONES DE FILESYSTEM ───
    if accion in ("crear_carpeta","borrar_carpeta","crear_archivo","editar_archivo",
                  "borrar_archivo","listar","leer_archivo","buscar_archivo"):
        try:
            ruta = resolver_ruta(base, ruta_rel) if ruta_rel else base
        except PermissionError as e:
            print(json.dumps({"estado": "error", "detalle": str(e)}))
            sys.exit(EXIT_ERROR)

        if accion == "crear_carpeta":
            os.makedirs(ruta, exist_ok=True)
            salida = "Carpeta creada: " + ruta
        elif accion == "borrar_carpeta":
            shutil.rmtree(ruta) if os.path.isdir(ruta) else None
            salida = "Carpeta borrada: " + ruta
        elif accion == "crear_archivo":
            os.makedirs(os.path.dirname(ruta) or base, exist_ok=True)
            with open(ruta, "w", encoding="utf-8") as f:
                f.write(accion_json.get("contenido") or "")
            salida = "Archivo creado: " + ruta
        elif accion == "editar_archivo":
            with open(ruta, "w", encoding="utf-8") as f:
                f.write(accion_json.get("contenido") or "")
            salida = "Archivo editado: " + ruta
        elif accion == "borrar_archivo":
            os.remove(ruta) if os.path.isfile(ruta) else None
            salida = "Archivo borrado: " + ruta
        elif accion == "listar":
            items = sorted(os.listdir(ruta)) if os.path.isdir(ruta) else []
            salida = "\n".join(("  [D] " if os.path.isdir(os.path.join(ruta,i)) else "  [F] ") + i for i in items) or "  (vacia)"
        elif accion == "leer_archivo":
            with open(ruta, "r", encoding="utf-8", errors="replace") as f:
                salida = f.read()
        elif accion == "buscar_archivo":
            nombre = os.path.basename(ruta_rel)
            enc = []
            for root, dirs, files in os.walk(base):
                for f in files:
                    if nombre.lower() in f.lower():
                        enc.append(os.path.join(root, f))
            salida = "Encontrados:\n" + "\n".join(enc) if enc else "No se encontro: " + nombre

    # ─── ACCIONES ADB (control del teléfono) ───
    elif accion == "abrir_app":
        app = (accion_json.get("app") or accion_json.get("package") or "").lower()
        package = APPS.get(app, app if "." in app else None)
        if not package:
            salida = "App desconocida: " + app
        else:
            adb(f"monkey -p {package} -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
            salida = "App abierta: " + package

    elif accion == "tap":
        x = accion_json.get("x", 0)
        y = accion_json.get("y", 0)
        adb(f"input tap {x} {y}")
        salida = f"Tap en ({x}, {y})"

    elif accion == "escribir":
        texto = accion_json.get("texto", "").replace(" ", "%s")
        adb(f"input text '{texto}'")
        salida = "Escrito: " + accion_json.get("texto", "")

    elif accion == "tecla":
        codigo = accion_json.get("codigo", 66)
        adb(f"input keyevent {codigo}")
        salida = f"Tecla {codigo}"

    elif accion == "volver":
        adb("input keyevent 4")
        salida = "Back"

    elif accion == "home":
        adb("input keyevent 3")
        salida = "Home"

    elif accion == "leer_pantalla":
        adb("uiautomator dump /sdcard/ui.xml >/dev/null 2>&1")
        xml = ejecutar_shell("adb shell cat /sdcard/ui.xml")
        import re
        textos = re.findall(r'text="([^"]+)"', xml)
        salida = "Textos en pantalla:\n" + "\n".join(t for t in textos if t.strip())

    elif accion == "screenshot":
        out = os.path.expanduser("~/cyberia_shot.png")
        ejecutar_shell(f"adb exec-out screencap -p > {out}")
        salida = "Screenshot guardado: " + out

    elif accion == "secuencia":
        acciones = accion_json.get("acciones", [])
        resultados = []
        for a in acciones:
            try:
                sub = json.dumps(a)
                proc = subprocess.run(["python3", __file__], input=sub, capture_output=True, text=True, timeout=30)
                resultados.append(proc.stdout.strip())
                import time
                time.sleep(a.get("espera", 0.5))
            except Exception as e:
                resultados.append(f"Error en paso: {e}")
        salida = "\n".join(resultados)

    elif accion == "info_sistema":
        kernel = ejecutar_shell("uname -a").strip()
        mem = ejecutar_shell("free -h").strip()
        bat = ejecutar_shell("termux-battery-status")
        try:
            bd = json.loads(bat)
            bat_txt = f"{bd.get('percentage','?')}% ({bd.get('status','?')})"
        except Exception:
            bat_txt = "?"
        salida = f"Sistema:\n{kernel}\n\nMemoria:\n{mem}\n\nBateria: {bat_txt}"

    elif accion == "vibrar":
        ms = accion_json.get("ms", 500)
        ejecutar_shell(f"termux-vibrate -d {ms}")
        salida = f"Vibrado {ms}ms"

    elif accion == "notificar":
        titulo = accion_json.get("titulo", "CyberIA")
        texto = accion_json.get("texto", "")
        ejecutar_shell(f'termux-notification -t "{titulo}" -c "{texto}"')
        salida = "Notificacion enviada"

    elif accion == "hablar":
        texto = accion_json.get("texto", "")
        ejecutar_shell(f'termux-tts-speak -l es "{texto}"')
        salida = f"Dicho: {texto}"

    elif accion == "linterna":
        estado = accion_json.get("estado", "on")
        ejecutar_shell(f"termux-torch {estado}")
        salida = f"Linterna {estado}"

    elif accion == "whatsapp":
        numero = accion_json.get("numero", "")
        texto = accion_json.get("texto", "").replace(" ", "%20")
        if not numero:
            salida = "Falta numero"
        else:
            ejecutar_shell(f'am start -a android.intent.action.VIEW -d "https://wa.me/{numero}?text={texto}"')
            salida = f"WhatsApp abierto para {numero}"

    else:
        salida = "Accion '" + str(accion) + "' no implementada."

    print(json.dumps({"estado": "ok", "salida": salida}, ensure_ascii=False))
    sys.exit(EXIT_OK)

def main():
    entrada = sys.stdin.read().strip()
    if not entrada:
        print(json.dumps({"estado": "error", "detalle": "Sin accion"}))
        sys.exit(EXIT_ERROR)
    try:
        accion_json = json.loads(entrada)
    except json.JSONDecodeError:
        print(json.dumps({"estado": "error", "detalle": "JSON invalido"}))
        sys.exit(EXIT_ERROR)
    if "error" in accion_json:
        print(json.dumps({"estado": "error", "detalle": accion_json["error"]}))
        sys.exit(EXIT_ERROR)
    ejecutar(accion_json, cargar_config(), cargar_seguridad())

if __name__ == "__main__":
    main()
