#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CYBERIA - CORE ENGINE (UNIFIED EXECUTION & AUTO-HEAL)
© 2026 Pablo Daniel De Luca — DNI 31.649.936
"""

import http.server
import socketserver
import json
import subprocess
import socket
import os
import shutil

PORT = 3180
HOST = "0.0.0.0" 
SHELL_MARKER = "\n---CYBERIA_END---\n"
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../config/commands.json")
DESTRUCTIVAS = {"rm", "shutil.rmtree", "borrar", "del", "mkfs", "dd"}

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def cargar_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"base_trabajo": "~/CyberIA_Workspace", "acciones": {}}

def base_trabajo(config):
    ruta = os.path.expanduser(config.get("base_trabajo", "~/CyberIA_Workspace"))
    os.makedirs(ruta, exist_ok=True)
    return ruta

def resolver_ruta(base, ruta_relativa):
    ruta_absoluta = os.path.normpath(os.path.join(base, ruta_relativa))
    if not ruta_absoluta.startswith(os.path.normpath(base)):
        raise PermissionError(f"Ruta fuera de la zona segura: {ruta_relativa}")
    return ruta_absoluta

class ShellSession:
    def __init__(self):
        self.process = None
        self.start_shell()

    def start_shell(self):
        self.process = subprocess.Popen(
            ["/bin/bash", "-i"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        self.process.stdin.write(f"echo '{SHELL_MARKER}'\n")
        self.process.stdin.flush()
        self.read_until_marker()

    def read_until_marker(self):
        output = ""
        while True:
            char = self.process.stdout.read(1)
            if not char: break
            output += char
            if output.endswith(SHELL_MARKER):
                break
        return output.replace(SHELL_MARKER, "").strip()

    def execute(self, comando):
        # Implementación de auto-recuperación del shell si el proceso ha muerto
        if self.process.poll() is not None:
            print("\n[!] Shell detectado como muerto. Reiniciando sesión...")
            self.start_shell()

        full_command = f"{comando} && echo '{SHELL_MARKER}' || echo '{SHELL_MARKER}'\n"
        self.process.stdin.write(full_command)
        self.process.stdin.flush()
        return self.read_until_marker()

session = ShellSession()

class AutonomoRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/execute':
            self.send_response(404)
            self.end_headers()
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        try:
            data = json.loads(post_data.decode('utf-8'))

            if isinstance(data, dict) and "accion" in data:
                resultado = self.procesar_accion_segura(data)
            else:
                comando = data.get('comando', '') if isinstance(data, dict) else str(data)
                resultado = self.procesar_bash_directo(comando)

            # Lógica de Bucle de Retroalimentación (Auto-Heal)
            # Si la salida contiene patrones de error comunes, marcamos el estado como 'error'
            # para que el LLM en el móvil active su modo de corrección.
            estado = "exito"
            error_patterns = ["command not found", "No such file or directory", "Permission denied", "Syntax error"]
            if any(pat.lower() in resultado.lower() for pat in error_patterns):
                estado = "error_bash"

            respuesta = {
                "estado": estado,
                "salida": resultado,
                "copyright": "© 2026 Pablo Daniel De Luca"
            }

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(respuesta).encode('utf-8'))

        except PermissionError as pe:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(json.dumps({"estado": "error", "detalle": str(pe)}).encode('utf-8'))
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(json.dumps({"estado": "error", "detalle": str(e)}).encode('utf-8'))

    def procesar_bash_directo(self, comando):
        if any(word in comando.lower() for word in DESTRUCTIVAS):
            return "ERROR: Comando destructivo detectado. Use una acción estructurada para borrar archivos."

        print(f"\n[+] CyberIA Shell Directo: {comando}")
        return session.execute(comando)

    def procesar_accion_segura(self, accion_json):
        config = cargar_config()
        accion = accion_json.get("accion")
        ruta_rel = accion_json.get("ruta") or ""
        base = base_trabajo(config)

        if accion not in config["acciones"]:
            return f"Accion desconocida: {accion}"

        try:
            ruta = resolver_ruta(base, ruta_rel) if ruta_rel else base
        except PermissionError as e:
            raise e

        print(f"\n[+] CyberIA Acción Segura: {accion} sobre {ruta_rel}")

        if accion == "crear_carpeta":
            return session.execute(f"mkdir -p '{ruta}'")
        elif accion == "borrar_carpeta":
            return session.execute(f"rm -rf '{ruta}'")
        elif accion == "crear_archivo":
            contenido = accion_json.get("contenido", "")
            return session.execute(f"echo '{contenido}' > '{ruta}'")
        elif accion == "editar_archivo":
            contenido = accion_json.get("contenido", "")
            return session.execute(f"echo '{contenido}' > '{ruta}'")
        elif accion == "borrar_archivo":
            return session.execute(f"rm '{ruta}'")
        elif accion == "listar":
            return session.execute(f"ls -la '{ruta}'")
        elif accion == "leer_archivo":
            return session.execute(f"cat '{ruta}'")
        else:
            return f"Accion '{accion}' implementada pero no mapeada a shell."

if __name__ == "__main__":
    local_ip = get_local_ip()
    print("=" * 50)
    print(" CYBERIA - UNIFIED CORE ENGINE (v2.0)")
    print(" © 2026 Pablo Daniel De Luca")
    print("=" * 50)
    print(f"[*] Servidor activo en: http://{local_ip}:{PORT}")
    print("[*] Desde tu móvil, usa esta IP para conectar.")
    print("[*] Presiona Ctrl+C para detener.\n")

    with socketserver.TCPServer((HOST, PORT), AutonomoRequestHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[!] Apagando CyberIA Core...")
            httpd.server_close()
if __name__ == "__main__":
    local_ip = get_local_ip()
    print("=" * 50)
    print(" AUTÓNOMO 3.18 - BRIDGE DE EJECUCIÓN")
    print(" © 2026 Pablo Daniel De Luca")
    print("=" * 50)
    print(f"[*] Servidor activo en: http://{local_ip}:{PORT}")
    print("[*] Desde tu móvil, usa esta IP para conectar.")
    print("[*] Presiona Ctrl+C para detener.\n")

    with socketserver.TCPServer((HOST, PORT), AutonomoRequestHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[!] Apagando Autónomo 3.18...")
            httpd.server_close()
