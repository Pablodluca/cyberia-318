#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# bridge.py - Servidor HTTP local para la UI de CyberIA 318
# © 2026 Pablo Daniel De Luca - Ink318 Software
import http.server, socketserver, json, subprocess, os, urllib.request, urllib.error
from pathlib import Path

B = Path.home() / "proyectos318"
WEB = B / "web"
PORT = 3180
CFG = B / "config" / "commands.json"

def cfg():
    try:
        with open(CFG, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"ollama_url": "http://127.0.0.1:11434", "modelo_charla": "cyberia318"}

def ollama_get(path):
    url = f"http://127.0.0.1:11434{path}"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        return {"error": str(e)}

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    def log_message(self, fmt, *args):
        pass  # silencioso

    def _json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/models":
            return self._json(ollama_get("/api/tags"))
        if self.path == "/api/system":
            try:
                kernel = subprocess.run("uname -m", shell=True, capture_output=True, text=True).stdout.strip()
                mem = subprocess.run("free -m | awk 'NR==2{print $2\" \"$7}'", shell=True, capture_output=True, text=True).stdout.strip().split()
                bat = subprocess.run("termux-battery-status", shell=True, capture_output=True, text=True).stdout
                try:
                    bd = json.loads(bat)
                except Exception:
                    bd = {}
                return self._json({
                    "kernel": kernel,
                    "ram_total_mb": int(mem[0]) if len(mem) > 0 else 0,
                    "ram_free_mb": int(mem[1]) if len(mem) > 1 else 0,
                    "battery": bd.get("percentage", -1),
                    "battery_status": bd.get("status", "?"),
                })
            except Exception as e:
                return self._json({"error": str(e)}, 500)
        if self.path == "/api/health":
            return self._json({"ok": True, "cyberia": "318"})
        # Archivos estáticos (web/)
        if self.path == "/":
            self.path = "/index.html"
        return super().do_GET()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        try:
            data = json.loads(raw) if raw else {}
        except Exception:
            data = {}

        if self.path == "/api/chat":
            return self._chat(data)
        if self.path == "/api/model":
            return self._set_model(data)
        return self._json({"error": "endpoint desconocido"}, 404)

    def _chat(self, data):
        texto = (data.get("message") or "").strip()
        modelo = data.get("model") or None
        if not texto:
            return self._json({"error": "mensaje vacío"}, 400)

        # 1. Router: texto → acción JSON
        try:
            r = subprocess.run(
                ["python3", str(B / "router.py"), texto],
                capture_output=True, text=True, timeout=90
            )
            if r.returncode != 0:
                return self._json({"error": r.stderr.strip() or "router falló"}, 500)
            accion = json.loads(r.stdout)
        except Exception as e:
            return self._json({"error": f"router: {e}"}, 500)

        # 2. ¿Acción válida o desconocida?
        nombre = accion.get("accion", "")
        meta = cfg().get("acciones", {}).get(nombre, {})

        if not meta:
            # No es acción → conversación vía Ollama
            modelo = modelo or cfg().get("modelo_charla", "cyberia318")
            try:
                payload = json.dumps({
                    "model": modelo,
                    "messages": [{"role": "user", "content": texto}],
                    "stream": False,
                }).encode()
                req = urllib.request.Request(
                    "http://127.0.0.1:11434/api/chat",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                )
                with urllib.request.urlopen(req, timeout=120) as resp:
                    rj = json.loads(resp.read().decode())
                return self._json({
                    "type": "chat",
                    "response": rj.get("message", {}).get("content", "").strip(),
                    "model": modelo,
                })
            except Exception as e:
                return self._json({"error": f"ollama: {e}"}, 500)

        # 3. Acción requiere confirmación
        if meta.get("destructiva") and not accion.get("confirmado"):
            return self._json({
                "type": "confirm",
                "pregunta": f"¿Confirmás {nombre} sobre {accion.get('ruta') or 'workspace'}?",
                "accion": accion,
            })

        # 4. Ejecutar
        try:
            e = subprocess.run(
                ["python3", str(B / "ejecutor.py")],
                input=json.dumps(accion),
                capture_output=True, text=True, timeout=60
            )
            salida = e.stdout.strip() or e.stderr.strip()
            try:
                out = json.loads(salida)
            except Exception:
                out = {"estado": "ok", "salida": salida}
            return self._json({"type": "action", "result": out})
        except Exception as ex:
            return self._json({"error": f"ejecutor: {ex}"}, 500)

    def _set_model(self, data):
        modelo = data.get("model")
        if not modelo:
            return self._json({"error": "modelo vacío"}, 400)
        try:
            with open(CFG, encoding="utf-8") as f:
                c = json.load(f)
            c["modelo_charla"] = modelo
            with open(CFG, "w", encoding="utf-8") as f:
                json.dump(c, f, indent=2, ensure_ascii=False)
            return self._json({"ok": True, "modelo": modelo})
        except Exception as e:
            return self._json({"error": str(e)}, 500)

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"🌐 CyberIA 318 activa en http://127.0.0.1:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n👋 Cerrando...")
