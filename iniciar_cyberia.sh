#!/data/data/com.termux/files/usr/bin/bash
#
# Copyright (c) 2026 Pablo Daniel De Luca
# Ink318 Software
# Email: dress318@gmail.com
# DNI: 31.649.936
# Todos los derechos reservados.
#
# iniciar_cyberia.sh
# Levanta Ollama con CORS abierto, sirve cyberia.html por HTTP local
# y lo abre en el navegador del celular. Pensado para correr en Termux.

set -e

# ---- CONFIG (ajustar si hace falta) ----
MODELO="ia318"              # cambiar por el tag real si "ia318" no existe (ej: dress318/318, Android_Artisan/Gemma3-Android:1b)
PUERTO_HTTP=8318
CARPETA_SITIO="$HOME/cyberia_app"
ARCHIVO_HTML="cyberia.html"
# -----------------------------------------

echo "════════════════════════════════════════"
echo "  CYBERIA · IA318 · Ink318 Software"
echo "════════════════════════════════════════"

# 1) Verificar que ollama esté instalado
if ! command -v ollama >/dev/null 2>&1; then
    echo "[ERROR] Ollama no está instalado en Termux."
    echo "        Instalalo antes de correr este script."
    exit 1
fi

# 2) Verificar que el modelo exista, avisar si no
if ! ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$MODELO"; then
    echo "[AVISO] El modelo '$MODELO' no aparece en 'ollama list'."
    echo "        Modelos disponibles:"
    ollama list 2>/dev/null || echo "        (no se pudo listar, ¿ollama serve corriendo?)"
    echo "        Editá la variable MODELO en este script si hace falta."
fi

# 3) Levantar ollama serve con CORS abierto para que el HTML pueda pegarle
#    (si ya está corriendo, no pasa nada, el bind falla y seguimos)
export OLLAMA_ORIGINS="*"
export OLLAMA_HOST="127.0.0.1:11434"

if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
    echo "[INFO] Iniciando ollama serve en background (OLLAMA_ORIGINS=*)..."
    nohup ollama serve > "$HOME/ollama_serve.log" 2>&1 &
    sleep 2
else
    echo "[INFO] ollama serve ya está corriendo."
fi

# 4) Preparar carpeta del sitio y copiar el HTML si no está
mkdir -p "$CARPETA_SITIO"
if [ ! -f "$CARPETA_SITIO/$ARCHIVO_HTML" ]; then
    if [ -f "$HOME/$ARCHIVO_HTML" ]; then
        cp "$HOME/$ARCHIVO_HTML" "$CARPETA_SITIO/$ARCHIVO_HTML"
    else
        echo "[ERROR] No encontré $ARCHIVO_HTML ni en $CARPETA_SITIO ni en $HOME."
        echo "        Copialo manualmente a $CARPETA_SITIO/ antes de correr el script."
        exit 1
    fi
fi

# 5) Servir el HTML por HTTP (evita el bloqueo CORS de file://)
if ! pgrep -f "http.server $PUERTO_HTTP" >/dev/null 2>&1; then
    echo "[INFO] Sirviendo $ARCHIVO_HTML en http://127.0.0.1:$PUERTO_HTTP ..."
    cd "$CARPETA_SITIO"
    nohup python -m http.server "$PUERTO_HTTP" --bind 127.0.0.1 > "$HOME/http_server.log" 2>&1 &
    sleep 1
else
    echo "[INFO] Servidor HTTP ya está corriendo en el puerto $PUERTO_HTTP."
fi

URL="http://127.0.0.1:$PUERTO_HTTP/$ARCHIVO_HTML"

echo "────────────────────────────────────────"
echo "  Modelo IA318 : $MODELO"
echo "  Ollama       : http://127.0.0.1:11434"
echo "  CyberIA      : $URL"
echo "────────────────────────────────────────"

# 6) Abrir en el navegador por defecto del celular
if command -v termux-open-url >/dev/null 2>&1; then
    termux-open-url "$URL"
else
    echo "[AVISO] termux-open-url no disponible (paquete termux-api)."
    echo "        Abrí manualmente: $URL"
fi

echo "[OK] CyberIA lista. Dejá esta terminal abierta para mantener los servicios vivos."
