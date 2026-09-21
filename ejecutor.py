# -*- coding: utf-8 -*-
# Copyright 2026 Pablo Daniel De Luca - Ink318 Software - dress318@gmail.com
# ejecutor.py - Autono318-Mobile
# Ejecuta la accion JSON que produce router.py sobre el filesystem

import sys
import os
import json
import shutil
import subprocess

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "commands.json")
DESTRUCTIVAS = {"borrar_carpeta", "borrar_archivo"}


def cargar_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def base_trabajo(config):
    ruta = os.path.expanduser(config.get("base_trabajo", "~/proyectos318"))
    os.makedirs(ruta, exist_ok=True)
    return ruta


def resolver_ruta(base, ruta_relativa):
    ruta_absoluta = os.path.normpath(os.path.join(base, ruta_relativa))
    if not ruta_absoluta.startswith(os.path.normpath(base)):
        raise PermissionError(f"Ruta fuera de la carpeta de trabajo: {ruta_relativa}")
    return ruta_absoluta


def confirmar(mensaje):
    print(f"WARNING  {mensaje} (escribi SI para confirmar): ", end="", flush=True)
    try:
        with open("/dev/tty", "r") as tty:
            respuesta = tty.readline().strip().lower()
    except OSError:
        return False
    return respuesta in ("si", "si")


def ejecutar(accion_json, config):
    accion = accion_json.get("accion")
    ruta_rel = accion_json.get("ruta") or ""
    base = base_trabajo(config)

    if accion not in config["acciones"]:
        print(f"Accion desconocida: {accion}")
        return

    if accion in DESTRUCTIVAS:
        if not confirmar(f"Vas a ejecutar '{accion}' sobre '{ruta_rel}'. Esto no se puede deshacer."):
            print("Cancelado.")
            return

    ruta = resolver_ruta(base, ruta_rel) if ruta_rel else base

    if accion == "crear_carpeta":
        os.makedirs(ruta, exist_ok=True)
        print(f"Carpeta creada: {ruta}")

    elif accion == "borrar_carpeta":
        if os.path.isdir(ruta):
            shutil.rmtree(ruta)
            print(f"Carpeta borrada: {ruta}")
        else:
            print(f"No existe la carpeta: {ruta}")

    elif accion == "crear_archivo":
        os.makedirs(os.path.dirname(ruta) or base, exist_ok=True)
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(accion_json.get("contenido") or "")
        print(f"Archivo creado: {ruta}")

    elif accion == "editar_archivo":
        if not os.path.isfile(ruta):
            print(f"No existe el archivo: {ruta}")
            return
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(accion_json.get("contenido") or "")
        print(f"Archivo editado: {ruta}")

    elif accion == "borrar_archivo":
        if os.path.isfile(ruta):
            os.remove(ruta)
            print(f"Archivo borrado: {ruta}")
        else:
            print(f"No existe el archivo: {ruta}")

    elif accion == "listar":
        if os.path.isdir(ruta):
            items = sorted(os.listdir(ruta))
            if items:
                for item in items:
                    tipo = "[D]" if os.path.isdir(os.path.join(ruta, item)) else "[F]"
                    print(f"  {tipo} {item}")
            else:
                print("  (carpeta vacia)")
        else:
            print(f"No existe la carpeta: {ruta}")

    elif accion == "leer_archivo":
        if os.path.isfile(ruta):
            with open(ruta, "r", encoding="utf-8", errors="replace") as f:
                contenido = f.read()
            print(f"[{ruta}]\n{'-'*40}\n{contenido}\n{'-'*40}")
        else:
            print(f"No existe el archivo: {ruta}")

    elif accion == "buscar_archivo":
        nombre = os.path.basename(ruta_rel) if ruta_rel else ""
        if not nombre:
            print("Especifica el nombre del archivo a buscar.")
            return
        encontrados = []
        for root, dirs, files in os.walk(base):
            for f in files:
                if nombre.lower() in f.lower():
                    encontrados.append(os.path.join(root, f))
        if encontrados:
            print("Encontrados:")
            for e in encontrados:
                print(f"  {e}")
        else:
            print(f"No se encontro '{nombre}' en {base}")

    elif accion == "info_sistema":
        resultado = subprocess.run("uname -a", shell=True, capture_output=True, text=True)
        mem = subprocess.run("free -h", shell=True, capture_output=True, text=True)
        bat = subprocess.run("termux-battery-status", shell=True, capture_output=True, text=True)
        print(f"Sistema:\n{resultado.stdout.strip()}")
        print(f"\nMemoria:\n{mem.stdout.strip()}")
        try:
            bat_data = json.loads(bat.stdout)
            print(f"\nBateria: {bat_data.get('percentage', '?')}% - {bat_data.get('status', '?')}")
        except Exception:
            pass

    elif accion == "compilar":
        comando = accion_json.get("comando")
        if not comando:
            print("No se especifico comando de compilacion.")
            return
        print(f"Ejecutando: {comando}")
        resultado = subprocess.run(comando, shell=True, cwd=ruta, capture_output=True, text=True)
        print(resultado.stdout)
        if resultado.returncode != 0:
            print(f"Error:\n{resultado.stderr}")


def main():
    entrada = sys.stdin.read().strip()
    if not entrada:
        print("No se recibio ninguna accion.")
        sys.exit(1)
    try:
        accion_json = json.loads(entrada)
    except json.JSONDecodeError:
        print(f"JSON invalido: {entrada}")
        sys.exit(1)
    if "error" in accion_json:
        print(f"El router reporto un error: {accion_json['error']}")
        sys.exit(1)
    config = cargar_config()
    ejecutar(accion_json, config)


if __name__ == "__main__":
    main()