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
