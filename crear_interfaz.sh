#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# crear_interfaz.sh - Genera la interfaz gráfica PWA de CyberIA 318
# © 2026 Pablo Daniel De Luca - Ink318 Software
# =============================================================================

set -e
B="$HOME/proyectos318"
WEB="$B/web"
mkdir -p "$WEB"

echo "🎨 Creando interfaz CyberIA 318..."

# ═════════════════════════════════════════════════════════════════
# 1. bridge.py — Servidor HTTP puente
# ═════════════════════════════════════════════════════════════════
cat > "$B/bridge.py" << 'BRIDGE_EOF'
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
BRIDGE_EOF
chmod +x "$B/bridge.py"

# ═════════════════════════════════════════════════════════════════
# 2. index.html — Estructura
# ═════════════════════════════════════════════════════════════════
cat > "$WEB/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0A0E17">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="manifest" href="manifest.json">
<link rel="stylesheet" href="theme.css">
<title>CyberIA 318</title>
</head>
<body>
<div class="app">

  <header class="header">
    <div class="brand">
      <span class="logo">⚡</span>
      <div>
        <div class="title">CYBERIA 318</div>
        <div class="subtitle" id="statusText">verificando...</div>
      </div>
    </div>
    <button class="icon-btn" id="settingsBtn" aria-label="Ajustes">⚙</button>
  </header>

  <div class="core-wrapper">
    <div class="core-sphere" id="coreSphere"></div>
  </div>

  <main class="messages" id="messages">
    <div class="msg system">
      <span>CyberIA 318 lista. Escribí o hablá.</span>
    </div>
  </main>

  <div class="quick-cmds">
    <button onclick="quick('¿Quién sos?')">¿Quién sos?</button>
    <button onclick="quick('Mostrame la info del sistema')">Sistema</button>
    <button onclick="quick('Lista la carpeta workspace')">Workspace</button>
  </div>

  <footer class="input-bar">
    <textarea id="prompt" placeholder="Escribí un comando..." rows="1"></textarea>
    <button class="send-btn" id="sendBtn" aria-label="Enviar">
      <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M2 21l21-9L2 3v7l15 2-15 2z"/></svg>
    </button>
  </footer>

</div>

<!-- Modal ajustes -->
<div class="modal" id="settingsModal">
  <div class="modal-content">
    <h3>⚙ Ajustes</h3>
    <label>Modelo
      <select id="modelSelect"></select>
    </label>
    <div class="info" id="systemInfo"></div>
    <button class="close-btn" onclick="closeSettings()">Cerrar</button>
  </div>
</div>

<script src="app.js"></script>
</body>
</html>
HTML_EOF

# ═════════════════════════════════════════════════════════════════
# 3. app.js — Lógica frontend
# ═════════════════════════════════════════════════════════════════
cat > "$WEB/app.js" << 'JS_EOF'
// © 2026 Pablo Daniel De Luca - Ink318 Software
const API = location.origin + "/api";
const $ = (id) => document.getElementById(id);
const messages = $("messages");
const prompt = $("prompt");
const sendBtn = $("sendBtn");
const statusText = $("statusText");
const coreSphere = $("coreSphere");
const modelSelect = $("modelSelect");
const settingsModal = $("settingsModal");
const systemInfo = $("systemInfo");

let currentModel = null;
let busy = false;

// ─── Init ───
async function init() {
  try {
    const r = await fetch(`${API}/health`);
    if (!r.ok) throw new Error();
    statusText.textContent = "en línea · local";
    coreSphere.classList.add("online");
  } catch {
    statusText.textContent = "sin conexión al motor";
    return;
  }
  loadModels();
  loadSystem();
}

async function loadModels() {
  try {
    const r = await fetch(`${API}/models`);
    const d = await r.json();
    const models = (d.models || []).map((m) => m.name);
    modelSelect.innerHTML = "";
    models.forEach((name) => {
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      modelSelect.appendChild(opt);
    });
    const pref = models.find((m) => m.startsWith("cyberia318")) || models[0];
    if (pref) {
      modelSelect.value = pref;
      currentModel = pref;
    }
  } catch (e) {
    console.warn("No se pudieron cargar modelos", e);
  }
}

async function loadSystem() {
  try {
    const r = await fetch(`${API}/system`);
    const d = await r.json();
    systemInfo.innerHTML = `
      <div><b>Arq:</b> ${d.kernel || "?"}</div>
      <div><b>RAM:</b> ${d.ram_free_mb} / ${d.ram_total_mb} MB libres</div>
      <div><b>Batería:</b> ${d.battery}% (${d.battery_status})</div>
    `;
  } catch {}
}

// ─── Chat ───
function addMsg(role, text) {
  const div = document.createElement("div");
  div.className = `msg ${role}`;
  div.textContent = text;
  messages.appendChild(div);
  messages.scrollTop = messages.scrollHeight;
  return div;
}

async function sendMessage(text) {
  if (busy) return;
  text = (text || "").trim();
  if (!text) return;
  busy = true;
  sendBtn.disabled = true;
  coreSphere.classList.add("thinking");

  addMsg("user", text);
  prompt.value = "";
  prompt.style.height = "auto";

  const loading = addMsg("ai", "▋ pensando...");

  try {
    const r = await fetch(`${API}/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: text, model: currentModel }),
    });
    const d = await r.json();

    if (d.error) {
      loading.textContent = `⚠ ${d.error}`;
    } else if (d.type === "chat") {
      loading.textContent = d.response || "(sin respuesta)";
    } else if (d.type === "action") {
      const sal = d.result?.salida || JSON.stringify(d.result);
      loading.textContent = `✓ ${sal}`;
    } else if (d.type === "confirm") {
      loading.textContent = `⚠ ${d.pregunta} (escribí "sí" para confirmar)`;
    } else {
      loading.textContent = JSON.stringify(d);
    }
  } catch (e) {
    loading.textContent = `⚠ Error de red: ${e.message}`;
  } finally {
    busy = false;
    sendBtn.disabled = false;
    coreSphere.classList.remove("thinking");
    messages.scrollTop = messages.scrollHeight;
  }
}

// ─── Eventos ───
sendBtn.addEventListener("click", () => sendMessage(prompt.value));
prompt.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    sendMessage(prompt.value);
  }
});
prompt.addEventListener("input", () => {
  prompt.style.height = "auto";
  prompt.style.height = Math.min(prompt.scrollHeight, 120) + "px";
});

window.quick = (t) => sendMessage(t);
window.closeSettings = () => settingsModal.classList.remove("open");
$("settingsBtn").addEventListener("click", () => {
  settingsModal.classList.add("open");
  loadSystem();
});
modelSelect.addEventListener("change", async () => {
  currentModel = modelSelect.value;
  await fetch(`${API}/model`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: currentModel }),
  });
});

init();
JS_EOF

# ═════════════════════════════════════════════════════════════════
# 4. theme.css — Estilo cyberpunk limpio
# ═════════════════════════════════════════════════════════════════
cat > "$WEB/theme.css" << 'CSS_EOF'
/* © 2026 Pablo Daniel De Luca - Ink318 Software */
:root{
  --bg:#0A0E17; --surface:#121826; --card:#1A2332;
  --cyan:#00E5FF; --cyan-glow:rgba(0,229,255,.4);
  --magenta:#FF0055; --magenta-glow:rgba(255,0,85,.4);
  --purple:#7000FF;
  --text:#E0F7FA; --text-dim:#80DEEA;
  --green:#00E676; --red:#FF1744;
  --font:'JetBrains Mono','Fira Code',ui-monospace,monospace;
  --safe-top:env(safe-area-inset-top,0px);
  --safe-bot:env(safe-area-inset-bottom,0px);
}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%;overflow:hidden}
body{
  font-family:var(--font);
  background:var(--bg);
  color:var(--text);
  background-image:
    radial-gradient(circle at 50% 20%, rgba(0,229,255,.08) 0%, transparent 50%),
    radial-gradient(circle at 20% 80%, rgba(255,0,85,.05) 0%, transparent 50%);
}
.app{
  display:flex;flex-direction:column;
  height:100vh;height:100dvh;
  padding-top:var(--safe-top);padding-bottom:var(--safe-bot);
}

/* Header */
.header{
  display:flex;align-items:center;justify-content:space-between;
  padding:12px 16px;
  background:linear-gradient(180deg,var(--card) 0%,transparent 100%);
  border-bottom:1px solid rgba(0,229,255,.15);
}
.brand{display:flex;align-items:center;gap:10px}
.logo{font-size:24px;filter:drop-shadow(0 0 8px var(--cyan-glow))}
.title{font-size:15px;font-weight:700;color:var(--cyan);letter-spacing:2px;text-shadow:0 0 10px var(--cyan-glow)}
.subtitle{font-size:10px;color:var(--text-dim);text-transform:uppercase;letter-spacing:1px;margin-top:2px}
.icon-btn{
  background:transparent;border:1px solid rgba(0,229,255,.3);
  color:var(--cyan);width:36px;height:36px;border-radius:50%;
  font-size:16px;cursor:pointer;transition:all .2s;
}
.icon-btn:active{background:rgba(0,229,255,.1)}

/* CyberCore */
.core-wrapper{display:flex;justify-content:center;padding:16px 0 8px;flex-shrink:0}
.core-sphere{
  width:80px;height:80px;border-radius:50%;
  background:radial-gradient(circle, rgba(255,255,255,.9) 0%, var(--purple) 40%, #000010 100%);
  border:2px solid rgba(0,229,255,.5);
  box-shadow:0 0 25px var(--cyan-glow), inset 0 0 12px var(--cyan-glow);
  animation:breathe 2s ease-in-out infinite alternate;
  transition:all .3s;
}
.core-sphere.online{
  border-color:var(--cyan);
  box-shadow:0 0 35px var(--cyan-glow), inset 0 0 15px var(--cyan);
}
.core-sphere.thinking{
  border-color:var(--magenta);
  background:radial-gradient(circle, rgba(255,255,255,.9) 0%, var(--magenta) 40%, #100010 100%);
  box-shadow:0 0 40px var(--magenta-glow);
  animation:breathe .6s ease-in-out infinite alternate;
}
@keyframes breathe{0%{transform:scale(.95)}100%{transform:scale(1.05)}}

/* Mensajes */
.messages{
  flex:1;overflow-y:auto;padding:12px 16px;
  display:flex;flex-direction:column;gap:10px;
  scroll-behavior:smooth;
}
.messages::-webkit-scrollbar{width:4px}
.messages::-webkit-scrollbar-thumb{background:var(--cyan);border-radius:2px}
.msg{
  max-width:88%;padding:10px 14px;border-radius:14px;
  font-size:13px;line-height:1.5;word-wrap:break-word;
  animation:fadeUp .25s ease;
  white-space:pre-wrap;
}
.msg.user{
  align-self:flex-end;
  background:linear-gradient(135deg, rgba(0,229,255,.15), rgba(112,0,255,.15));
  border:1px solid rgba(0,229,255,.3);
  border-bottom-right-radius:4px;
  color:var(--text);
}
.msg.ai{
  align-self:flex-start;
  background:rgba(26,35,50,.8);
  border:1px solid rgba(255,0,85,.25);
  border-bottom-left-radius:4px;
  color:var(--text);
}
.msg.system{
  align-self:center;text-align:center;
  font-size:11px;color:var(--text-dim);
  background:transparent;border:none;
  opacity:.7;
}
@keyframes fadeUp{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}

/* Quick cmds */
.quick-cmds{
  display:flex;gap:8px;padding:8px 16px;overflow-x:auto;
  scrollbar-width:none;flex-shrink:0;
}
.quick-cmds::-webkit-scrollbar{display:none}
.quick-cmds button{
  flex-shrink:0;
  background:rgba(0,229,255,.08);border:1px solid rgba(0,229,255,.25);
  color:var(--text-dim);font-family:var(--font);font-size:11px;
  padding:6px 12px;border-radius:20px;cursor:pointer;
  transition:all .2s;white-space:nowrap;
}
.quick-cmds button:active{background:rgba(0,229,255,.2);color:var(--text)}

/* Input bar */
.input-bar{
  display:flex;gap:8px;padding:12px 16px;align-items:flex-end;
  background:linear-gradient(0deg,var(--card) 0%,transparent 100%);
  border-top:1px solid rgba(0,229,255,.15);
  flex-shrink:0;
}
#prompt{
  flex:1;background:var(--surface);border:1px solid rgba(0,229,255,.3);
  color:var(--text);font-family:var(--font);font-size:13px;
  padding:10px 14px;border-radius:20px;resize:none;
  max-height:120px;outline:none;transition:all .2s;line-height:1.4;
}
#prompt:focus{border-color:var(--cyan);box-shadow:0 0 10px var(--cyan-glow)}
.send-btn{
  width:42px;height:42px;border-radius:50%;flex-shrink:0;
  background:linear-gradient(135deg,var(--cyan),var(--purple));
  border:none;color:var(--bg);cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  box-shadow:0 0 15px var(--cyan-glow);transition:all .2s;
}
.send-btn:active{transform:scale(.92)}
.send-btn:disabled{opacity:.5;cursor:not-allowed}

/* Modal */
.modal{
  position:fixed;inset:0;background:rgba(0,0,0,.75);
  display:none;align-items:center;justify-content:center;
  padding:20px;z-index:100;backdrop-filter:blur(4px);
}
.modal.open{display:flex}
.modal-content{
  background:var(--card);border:1px solid rgba(0,229,255,.3);
  border-radius:20px;padding:20px;width:100%;max-width:340px;
  box-shadow:0 0 40px rgba(0,229,255,.2);
}
.modal-content h3{color:var(--cyan);font-size:16px;margin-bottom:16px;letter-spacing:1px}
.modal-content label{display:block;font-size:11px;color:var(--text-dim);margin-bottom:12px}
#modelSelect{
  width:100%;margin-top:6px;padding:8px;
  background:var(--surface);border:1px solid rgba(0,229,255,.3);
  color:var(--text);font-family:var(--font);font-size:12px;
  border-radius:8px;outline:none;
}
.info{font-size:11px;color:var(--text-dim);line-height:1.7;margin:12px 0;padding:10px;background:rgba(0,0,0,.3);border-radius:8px}
.info b{color:var(--cyan)}
.close-btn{
  width:100%;margin-top:8px;padding:10px;
  background:rgba(0,229,255,.15);border:1px solid rgba(0,229,255,.3);
  color:var(--text);font-family:var(--font);font-size:12px;
  border-radius:10px;cursor:pointer;transition:all .2s;
}
.close-btn:active{background:rgba(0,229,255,.25)}
CSS_EOF

# ═════════════════════════════════════════════════════════════════
# 5. manifest.json — PWA
# ═════════════════════════════════════════════════════════════════
cat > "$WEB/manifest.json" << 'MANIFEST_EOF'
{
  "name": "CyberIA 318",
  "short_name": "CyberIA",
  "description": "Asistente local de Pablo Daniel De Luca · Ink318 Software",
  "start_url": "/",
  "display": "standalone",
  "orientation": "portrait",
  "background_color": "#0A0E17",
  "theme_color": "#0A0E17",
  "icons": [
    {
      "src": "icon.svg",
      "sizes": "any",
      "type": "image/svg+xml",
      "purpose": "any maskable"
    }
  ]
}
MANIFEST_EOF

# ═════════════════════════════════════════════════════════════════
# 6. icon.svg — Ícono de la app
# ═════════════════════════════════════════════════════════════════
cat > "$WEB/icon.svg" << 'ICON_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 192 192">
  <rect width="192" height="192" fill="#0A0E17" rx="32"/>
  <circle cx="96" cy="96" r="70" fill="none" stroke="#00E5FF" stroke-width="2" opacity="0.3"/>
  <circle cx="96" cy="96" r="55" fill="none" stroke="#00E5FF" stroke-width="1.5" opacity="0.5" stroke-dasharray="4 4"/>
  <circle cx="96" cy="96" r="40" fill="url(#grad)"/>
  <path d="M88 60 L110 60 L98 88 L118 88 L86 134 L94 100 L74 100 Z"
        fill="#0A0E17" stroke="#00E5FF" stroke-width="1.5" stroke-linejoin="round"/>
  <defs>
    <radialGradient id="grad">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.9"/>
      <stop offset="50%" stop-color="#7000FF"/>
      <stop offset="100%" stop-color="#000010"/>
    </radialGradient>
  </defs>
</svg>
ICON_EOF

# ═════════════════════════════════════════════════════════════════
# 7. arrancar.sh — Levanta todo
# ═════════════════════════════════════════════════════════════════
cat > "$B/arrancar.sh" << 'START_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# arrancar.sh - Levanta CyberIA 318 completa
# © 2026 Pablo Daniel De Luca - Ink318 Software
B="$HOME/proyectos318"

# 1. Ollama (arranca si no está)
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "🚀 Arrancando Ollama..."
    nohup ollama serve > "$B/logs/ollama.log" 2>&1 &
    sleep 3
fi
echo "✓ Ollama OK"

# 2. Bridge (matar si existe y rearrancar)
pkill -f "bridge.py" 2>/dev/null
sleep 1
nohup python3 "$B/bridge.py" > "$B/logs/bridge.log" 2>&1 &
sleep 2
if curl -sf http://127.0.0.1:3180/api/health >/dev/null 2>&1; then
    echo "✓ Bridge OK  →  http://127.0.0.1:3180"
else
    echo "✗ Bridge falló. Ver: $B/logs/bridge.log"
    exit 1
fi

# 3. Abrir en el navegador
URL="http://127.0.0.1:3180"
if command -v termux-open-url >/dev/null 2>&1; then
    termux-open-url "$URL"
    echo "🌐 Abriendo $URL en el navegador"
else
    echo "🌐 Abrí manualmente: $URL"
fi

echo ""
echo "════════════════════════════════════════"
echo "  ⚡ CyberIA 318 corriendo"
echo "════════════════════════════════════════"
echo "  UI Web   : $URL"
echo "  Logs     : $B/logs/"
echo "  Detener  : pkill -f bridge.py"
echo "════════════════════════════════════════"
START_EOF
chmod +x "$B/arrancar.sh"

echo ""
echo "✅ Interfaz creada en $WEB/"
echo ""
echo "📋 Para arrancar:"
echo "   bash $B/arrancar.sh"
echo ""
echo "📱 Para instalar como app (una sola vez):"
echo "   1. Abrí http://127.0.0.1:3180 en Chrome"
echo "   2. Menú (⋮) → 'Agregar a pantalla de inicio'"
echo "   3. Listo, aparece el ícono ⚡ de CyberIA"
