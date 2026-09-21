#!/data/data/com.termux/files/usr/bin/bash
#
# Copyright (c) 2026 Pablo Daniel De Luca
# Ink318 Software
# Email: dress318@gmail.com
# DNI: 31.649.936
# Todos los derechos reservados.
#
# escucha318.sh
# Asistente de voz en background para Termux: escucha todo el tiempo,
# detecta la wake-word "318", y para cada comando decide entre:
#   1) ejecutarlo como acción real (cámara, WhatsApp, etc.) vía tu agente
#      existente (router.py + ejecutor.py, alias `ia`)
#   2) responder conversacionalmente vía IA318 (Ollama) si no es una
#      acción reconocida
# Reconocimiento de voz 100% offline con whisper.cpp (sin Google).
# Requiere haber corrido antes instalar_whisper.sh una vez.

set -u
shopt -s expand_aliases

# Los scripts no interactivos no cargan ~/.bashrc por default, así que
# los alias como `ia` no existen a menos que los carguemos a mano.
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ -f "$HOME/.bash_aliases" ] && source "$HOME/.bash_aliases"
[ -f "$HOME/.profile" ] && source "$HOME/.profile"

# ================= CONFIG =================
# Modelo liviano para charla fluida (según tu setup, el que no tira
# broken pipe por RAM en este teléfono)
MODELO_CONVERSACIONAL="Android_Artisan/Gemma3-Android:1b"
OLLAMA_ENDPOINT="http://127.0.0.1:11434/api/chat"

# --- Reconocimiento de voz offline (whisper.cpp) ---
CARPETA_WHISPER="$HOME/whisper.cpp"
MODELO_WHISPER="$CARPETA_WHISPER/models/ggml-base.bin"
WHISPER_BIN=""
if [ -f "$CARPETA_WHISPER/build/bin/whisper-cli" ]; then
    WHISPER_BIN="$CARPETA_WHISPER/build/bin/whisper-cli"
elif [ -f "$CARPETA_WHISPER/main" ]; then
    WHISPER_BIN="$CARPETA_WHISPER/main"
fi
AUDIO_TMP="$HOME/.318_audio"
DURACION_WAKE=4   # segundos que escucha cada ciclo esperando la wake word
DURACION_CMD=5    # segundos que escucha después de la wake word

# Wake word para activar el modo autónomo (una sola vez, después queda
# escuchando todo sin repetirla)
WAKE_WORDS=("autonomo")

# Frases para volver a modo dormido (deja de procesar todo lo que digas
# como comando, vuelve a esperar la wake word)
EXIT_WORDS=("eso es todo" "es todo por hoy" "gracias eso es todo" "dejar de escuchar" "nada mas gracias" "listo gracias" "por hoy es todo")

# AJUSTAR ESTO según lo que realmente devuelva tu comando `ia`:
# - Si `ia "texto"` NO reconoce el texto como acción, ¿qué frase imprime?
#   (para saber cuándo caer a modo conversacional en vez de acción)
PATRON_SIN_ACCION="no.*(entend|reconoc)|accion.*no.*encontrada|comando no valido"

# AJUSTAR ESTO según cómo pide confirmación tu ejecutor.py antes de
# acciones destructivas (la palabra clave que espera, típicamente "SI")
PATRON_CONFIRMACION="confirm|si.*continuar|estas seguro"

MAX_HISTORIAL=6   # mensajes de contexto que se mandan al modelo conversacional
# ============================================

# --- Verificaciones previas ---
if [ -z "$WHISPER_BIN" ] || [ ! -f "$MODELO_WHISPER" ]; then
    echo "[ERROR] No encuentro whisper.cpp compilado o el modelo."
    echo "        Corré primero: bash instalar_whisper.sh"
    exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "[ERROR] Falta ffmpeg. Instalalo: pkg install ffmpeg"
    exit 1
fi
if ! command -v termux-microphone-record >/dev/null 2>&1 || ! command -v termux-tts-speak >/dev/null 2>&1; then
    echo "[ERROR] Falta termux-api. Instalá el paquete: pkg install termux-api"
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "[INFO] Instalando jq (necesario para parsear respuestas de Ollama)..."
    pkg install -y jq >/dev/null 2>&1
fi
if ! type ia >/dev/null 2>&1; then
    echo "[AVISO] No encuentro el alias/comando 'ia' ni siquiera después de cargar .bashrc."
    echo "        Buscá dónde está definido (grep -n 'alias ia=' ~/.bashrc) y avisame,"
    echo "        o cambiá directamente la función ejecutar_accion() más abajo para que"
    echo "        llame a tu script real, ej: bash ~/proyectos318/asistente.sh \"\$texto\""
fi

termux-wake-lock
trap 'echo "[318] Apagando..."; termux-tts-speak -l es "Hasta luego, Pablo."; termux-wake-unlock; exit 0' INT TERM

echo "════════════════════════════════════════"
echo "  318 · Asistente personal · escuchando (offline)"
echo "  Decí \"318\" para activar"
echo "════════════════════════════════════════"

# Frases que whisper "alucina" cuando hay silencio/ruido de fondo (no son
# voz real, hay que descartarlas)
PATRON_ALUCINACION='^\s*(\[.*\]|\(.*\)|¡?[Aa]y[e]?!?|subt[ií]tulos.*|gracias por ver.*|m[uú]sica)\s*$'

UMBRAL_SILENCIO_DB="-35"   # más negativo = más sensible (capta susurros pero también ruido)

# Graba $1 segundos de audio y devuelve el texto transcripto por whisper.cpp
# (vacío si detecta silencio o si whisper alucina texto típico de silencio)
escuchar() {
    local duracion="$1"
    rm -f "$AUDIO_TMP.m4a" "$AUDIO_TMP.wav"

    termux-microphone-record -f "$AUDIO_TMP.m4a" -l "$duracion" -e aac -r 16000 -c 1 >/dev/null 2>&1
    sleep "$((duracion + 1))"
    termux-microphone-record -q >/dev/null 2>&1

    if [ ! -f "$AUDIO_TMP.m4a" ]; then
        echo ""
        return
    fi

    ffmpeg -y -loglevel error -i "$AUDIO_TMP.m4a" -ar 16000 -ac 1 -c:a pcm_s16le "$AUDIO_TMP.wav" 2>/dev/null

    if [ ! -f "$AUDIO_TMP.wav" ]; then
        echo ""
        return
    fi

    # Filtro de energía: si no hubo volumen real, ni molestamos a whisper
    # (esto es lo que evita la mayoría de las alucinaciones "[Música]")
    local max_vol
    max_vol=$(ffmpeg -i "$AUDIO_TMP.wav" -af volumedetect -f null /dev/null 2>&1 \
        | grep "max_volume" | grep -oE '\-?[0-9]+(\.[0-9]+)?' | head -1)

    if [ -n "$max_vol" ]; then
        # comparación en coma flotante con awk (bash no sabe de decimales)
        if awk -v a="$max_vol" -v b="$UMBRAL_SILENCIO_DB" 'BEGIN{exit !(a<b)}'; then
            echo ""
            return
        fi
    fi

    local texto
    texto=$("$WHISPER_BIN" -m "$MODELO_WHISPER" -f "$AUDIO_TMP.wav" -l es -nt 2>/dev/null \
        | sed '/^\s*$/d' | tr -d '\n')

    # Descartar alucinaciones típicas de silencio/ruido
    if echo "$texto" | grep -qiE "$PATRON_ALUCINACION"; then
        echo ""
        return
    fi

    echo "$texto"
}

echo "[DEBUG] Probando el micrófono $DURACION_WAKE seg (decí cualquier cosa)..."
prueba="$(escuchar "$DURACION_WAKE")"
if [ -z "$prueba" ]; then
    echo "[AVISO] No se transcribió nada. Puede ser permiso de mic o algo del audio."
    echo "        Seguimos igual, pero si esto se repite en el loop, revisá permisos."
else
    echo "[DEBUG] Se escuchó: \"$prueba\""
fi

# Historial de conversación para el modo charla (array plano rol|contenido)
declare -a HISTORIAL=()

normalizar() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[.,;!¡¿?]//g' | sed 'y/áéíóúñ/aeioun/'
}

contiene_alguna() {
    local texto_norm="$1"
    shift
    for w in "$@"; do
        if [[ "$texto_norm" == *"$w"* ]]; then
            return 0
        fi
    done
    return 1
}

# Saca la wake word del texto y devuelve lo que sobra (si vino todo junto:
# "autónomo, abrime la cámara")
extraer_comando() {
    local texto_norm="$1"
    local resto="$texto_norm"
    for w in "${WAKE_WORDS[@]}"; do
        resto="${resto//$w/}"
    done
    resto="$(echo "$resto" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    echo "$resto"
}

# Llama a tu agente de acciones existente (~/asistente.sh texto "instrucción")
ejecutar_accion() {
    local texto="$1"
    ia texto "$texto" 2>&1
}

# Charla fluida con IA318 (razonamiento, no acciones), manteniendo contexto corto
consultar_conversacional() {
    local texto="$1"
    HISTORIAL+=("user|$texto")

    # Armar el JSON de mensajes a partir del historial
    local mensajes='[{"role":"system","content":"Sos 318, el asistente personal de voz de Pablo (Ink318 Software). Respondé en español rioplatense, corto y directo, como para escuchar en voz alta, sin markdown ni listas."}'
    local i=0
    local total=${#HISTORIAL[@]}
    local desde=$(( total > MAX_HISTORIAL ? total - MAX_HISTORIAL : 0 ))
    for ((i=desde; i<total; i++)); do
        local rol="${HISTORIAL[$i]%%|*}"
        local contenido="${HISTORIAL[$i]#*|}"
        contenido="${contenido//\"/\\\"}"
        mensajes="$mensajes,{\"role\":\"$rol\",\"content\":\"$contenido\"}"
    done
    mensajes="$mensajes]"

    local respuesta
    respuesta=$(curl -s "$OLLAMA_ENDPOINT" -d "{\"model\":\"$MODELO_CONVERSACIONAL\",\"messages\":$mensajes,\"stream\":false}" | jq -r '.message.content // "No pude pensar la respuesta."')

    HISTORIAL+=("assistant|$respuesta")
    echo "$respuesta"
}

procesar_comando() {
    local texto="$1"
    [ -z "$texto" ] && return
    echo "[VOS] $texto"

    local salida_accion
    salida_accion="$(ejecutar_accion "$texto")"
    local salida_norm
    salida_norm="$(normalizar "$salida_accion")"

    local respuesta_final=""

    if [[ -z "$salida_accion" ]] || echo "$salida_norm" | grep -qiE "$PATRON_SIN_ACCION"; then
        # No fue reconocido como acción -> modo conversacional
        respuesta_final="$(consultar_conversacional "$texto")"
    elif echo "$salida_norm" | grep -qiE "$PATRON_CONFIRMACION"; then
        # El ejecutor pide confirmación antes de algo destructivo
        termux-tts-speak -l es "$salida_accion"
        echo "[318] $salida_accion (esperando confirmación por voz)"
        local confirmacion
        confirmacion="$(escuchar "$DURACION_CMD")"
        local confirmacion_norm
        confirmacion_norm="$(normalizar "$confirmacion")"
        if [[ "$confirmacion_norm" == *"si"* ]]; then
            respuesta_final="$(ejecutar_accion "SI")"
        else
            respuesta_final="Cancelado."
        fi
    else
        respuesta_final="$salida_accion"
    fi

    echo "[318] $respuesta_final"
    termux-tts-speak -l es "$respuesta_final"
}

# --- Loop principal: máquina de estados dormido / activo ---
# DORMIDO: solo escucha esperando la wake word "autónomo", ignora todo lo demás
# ACTIVO:  procesa cada frase como comando/charla, sin repetir la wake word,
#          hasta que digas una de las EXIT_WORDS ("eso es todo", etc.)
ESTADO="dormido"

while true; do
    if [ "$ESTADO" = "dormido" ]; then
        frase_raw="$(escuchar "$DURACION_WAKE")"
        [ -z "$frase_raw" ] && continue

        echo "[DEBUG] (dormido) escuché: \"$frase_raw\""
        frase_norm="$(normalizar "$frase_raw")"

        if contiene_alguna "$frase_norm" "${WAKE_WORDS[@]}"; then
            ESTADO="activo"
            echo "[318] Modo autónomo activado."
            termux-tts-speak -l es "Estoy en modo autónomo. Decime qué necesitás."

            comando_incluido="$(extraer_comando "$frase_norm")"
            if [ -n "$comando_incluido" ]; then
                # Vino todo junto: "autónomo, abrime la cámara"
                procesar_comando "$comando_incluido"
            fi
        fi

    else  # ESTADO = activo
        frase_raw="$(escuchar "$DURACION_CMD")"
        [ -z "$frase_raw" ] && continue

        echo "[DEBUG] (activo) escuché: \"$frase_raw\""
        frase_norm="$(normalizar "$frase_raw")"

        if contiene_alguna "$frase_norm" "${EXIT_WORDS[@]}"; then
            ESTADO="dormido"
            echo "[318] Modo autónomo desactivado, quedo esperando."
            termux-tts-speak -l es "Listo, quedo en espera. Decime autónomo cuando me necesites."
            continue
        fi

        procesar_comando "$frase_raw"
    fi
done
