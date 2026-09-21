# -*- coding: utf-8 -*-
# Copyright 2026 Pablo Daniel De Luca - Ink318 Software - dress318@gmail.com
# router.py - Autono318-Mobile
# Traduce lenguaje natural a JSON via Ollama REST API (sin CLI)

import sys
import json
import urllib.request

MODELO = "qwen2.5:1.5b"
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"

PROMPT_BASE = """Sos un router de comandos. Solo respondés JSON, sin texto extra, sin backticks.

Acciones validas: crear_carpeta, borrar_carpeta, crear_archivo, editar_archivo, borrar_archivo, listar, leer_archivo, buscar_archivo, info_sistema, compilar

Formato EXACTO (solo esto):
{"accion":"<accion>","ruta":"<ruta relativa o null>","contenido":"<texto o null>","comando":"<shell o null>"}

Ejemplos:
- "lista la carpeta easyclear_v2" -> {"accion":"listar","ruta":"easyclear_v2","contenido":null,"comando":null}
- "datos del celular" -> {"accion":"info_sistema","ruta":null,"contenido":null,"comando":null}
- "lee main.py de easyclear_v2" -> {"accion":"leer_archivo","ruta":"easyclear_v2/main.py","contenido":null,"comando":null}
- "crea carpeta test" -> {"accion":"crear_carpeta","ruta":"test","contenido":null,"comando":null}
- "busca config.json" -> {"accion":"buscar_archivo","ruta":"config.json","contenido":null,"comando":null}

Nunca uses rutas absolutas. Solo rutas relativas dentro de la carpeta de trabajo."""


def preguntar_modelo(instruccion):
    prompt = PROMPT_BASE + "\n\nInstruccion: " + instruccion + "\n\nJSON:"
    payload = {
        "model": MODELO,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.1, "num_predict": 150}
    }
    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    salida = data.get("response", "").strip()
    inicio = salida.find("{")
    fin = salida.rfind("}")
    if inicio == -1 or fin == -1:
        raise ValueError("El modelo no devolvio JSON valido:\n" + salida)
    return json.loads(salida[inicio:fin + 1])


def main():
    if len(sys.argv) < 2:
        print("Uso: python router.py \"instruccion\"")
        sys.exit(1)
    instruccion = " ".join(sys.argv[1:])
    try:
        accion = preguntar_modelo(instruccion)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    print(json.dumps(accion, ensure_ascii=False))


if __name__ == "__main__":
    main()