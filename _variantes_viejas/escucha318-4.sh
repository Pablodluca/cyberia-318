#!/data/data/com.termux/files/usr/bin/bash
#
# Copyright (c) 2026 Pablo Daniel De Luca
# Ink318 Software
# Email: dress318@gmail.com
# DNI: 31.649.936
# Todos los derechos reservados.
#
# escucha318.sh
# Asistente personal para Termux. Al arrancar, elegís si querés hablarle
# (reconocimiento offline con whisper.cpp) o escribirle directo (más
# rápido, sin esperar transcripción). En modo voz: detecta la wake-word
# "autónomo", y desde ahí procesa todo lo que digas (acción real vía tu
# agente, o charla vía IA318/Ollama) hasta que digas una frase de salida.

set -u
shopt -s expand_aliases

[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ -f "$HOME/.bash_aliases" ] && source "$HOME/.bash_aliases"
[ -f "$HOME/.profile" ] && source "$HOME/.profile"

# ================= CONFIG =================
MODELO_CONVERSACIONAL="Android_Artisan/Gemma3-Android:1b"
OLLAMA_ENDPOINT="http://127.0.0.1:11434/api/chat"

CARPETA_WHISPER="$HOME/whisper.cpp"
MODELO_WHISPER="$CARPETA_WHISPER/models/ggml-small.bin"
WHISPER_BIN=""
if [ -f "$CARPETA_WHISPER/build/bin/whisper-cli" ]; then
    WHISPER_BIN="$CARPETA_WHISPER/build/bin/whisper-cli"
elif [ -f "$CARPETA_WHISPER/main" ]; then
    WHISPER_BIN="$CARPETA_WHISPER/main"
fi
AUDIO_TMP="$HOME/.318_audio"
DURACION_WAKE=4
DURACION_CMD=5

WAKE_WORDS=("autonomo")
EXIT_WORDS=("eso es todo" "es todo por hoy" "gracias eso es todo" "dejar de escuchar" "nada mas gracias" "listo gracias" "por hoy es todo")

# AJUSTAR según lo que devuelva tu comando `ia` / router.py:
PATRON_SIN_ACCION="no.*(entend|reconoc|reconozc)|accion.*no.*encontrada|comando no valido"
PATRON_CONFIRMACION="confirm|si.*continuar|estas seguro"

MAX_HISTORIAL=6
# ============================================

ASISTENTE_DIR="$HOME/Asistente_318"

verificar_dependencias_voz() {
    if [ -z "$WHISPER_BIN" ] || [ ! -f "$MODELO_WHISPER" ]; then
        echo "[ERROR] No encuentro whisper.cpp compilado o el modelo."
        echo "        Corré primero: bash instalar_whisper.sh"
        return 1
    fi
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "[ERROR] Falta ffmpeg. Instalalo: pkg install ffmpeg"
        return 1
    fi
    if ! command -v termux-microphone-record >/dev/null 2>&1 || ! command -v termux-tts-speak >/dev/null 2>&1; then
        echo "[ERROR] Falta termux-api. Instalá el paquete: pkg install termux-api"
        return 1
    fi
    return 0
}

if ! command -v jq >/dev/null 2>&1; then
    echo "[INFO] Instalando jq..."
    pkg install -y jq >/dev/null 2>&1
fi

termux-wake-lock 2>/dev/null
trap 'echo "[318] Apagando..."; termux-tts-speak -l es "Hasta luego, Pablo." 2>/dev/null; termux-wake-unlock 2>/dev/null; exit 0' INT TERM

PATRON_ALUCINACION='^\s*(\[.*\]|\(.*\)|¡?[Aa]y[e]?!?|subt[ií]tulos.*|gracias por ver.*|m[uú]sica)\s*$'
UMBRAL_SILENCIO_DB="-35"

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

    local max_vol
    max_vol=$(ffmpeg -i "$AUDIO_TMP.wav" -af volumedetect -f null /dev/null 2>&1 \
        | grep "max_volume" | grep -oE '\-?[0-9]+(\.[0-9]+)?' | head -1)

    if [ -n "$max_vol" ]; then
        if awk -v a="$max_vol" -v b="$UMBRAL_SILENCIO_DB" 'BEGIN{exit !(a<b)}'; then
            echo ""
            return
        fi
    fi

    local texto
    texto=$("$WHISPER_BIN" -m "$MODELO_WHISPER" -f "$AUDIO_TMP.wav" -l es -nt 2>/dev/null \
        | sed '/^\s*$/d' | tr -d '\n')

    if echo "$texto" | grep -qiE "$PATRON_ALUCINACION"; then
        echo ""
        return
    fi

    echo "$texto"
}

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

extraer_comando() {
    local texto_norm="$1"
    local resto="$texto_norm"
    for w in "${WAKE_WORDS[@]}"; do
        resto="${resto//$w/}"
    done
    resto="$(echo "$resto" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    echo "$resto"
}

ejecutar_accion() {
    local texto="$1"
    local salida
    salida=$(printf '%s\nsalir\n' "$texto" | bash "$ASISTENTE_DIR/asistente.sh" 2>/dev/null \
        | grep -v "^Autono318-Mobile\." \
        | grep -v "^== Interpretando ==$" \
        | sed '/^$/d')
    echo "$salida"
}

consultar_conversacional() {
    local texto="$1"
    HISTORIAL+=("user|$texto")

    local mensajes='[{"role":"system","content":"Sos 318, el asistente personal de Pablo (Ink318 Software). Respondé en español rioplatense, corto y directo, sin markdown ni listas."}'
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

# modo_voz: si es 1, además de imprimir, habla por TTS
procesar_comando() {
    local texto="$1"
    local modo_voz="${2:-0}"
    [ -z "$texto" ] && return
    echo "[VOS] $texto"

    local salida_accion
    salida_accion="$(ejecutar_accion "$texto")"
    local salida_norm
    salida_norm="$(normalizar "$salida_accion")"

    local respuesta_final=""

    if [[ -z "$salida_accion" ]] || echo "$salida_norm" | grep -qiE "$PATRON_SIN_ACCION"; then
        respuesta_final="$(consultar_conversacional "$texto")"
    elif echo "$salida_norm" | grep -qiE "$PATRON_CONFIRMACION"; then
        [ "$modo_voz" = "1" ] && termux-tts-speak -l es "$salida_accion"
        echo "[318] $salida_accion (confirmás? si/no)"
        local confirmacion
        if [ "$modo_voz" = "1" ]; then
            confirmacion="$(escuchar "$DURACION_CMD")"
        else
            read -r -p "vos> " confirmacion
        fi
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
    [ "$modo_voz" = "1" ] && termux-tts-speak -l es "$respuesta_final"
}

# ──────────────────────────────────────────────────────────────
# MODO TEXTO: sin wake-word, sin whisper. Escribís y listo.
# ──────────────────────────────────────────────────────────────
bucle_texto() {
    echo "════════════════════════════════════════"
    echo "  318 · modo texto"
    echo "  Escribí tu pedido. 'salir' para terminar."
    echo "════════════════════════════════════════"
    while true; do
        read -r -p "vos> " entrada
        [ -z "$entrada" ] && continue
        if [[ "$(normalizar "$entrada")" == "salir" ]]; then
            echo "[318] Listo, nos vemos."
            break
        fi
        procesar_comando "$entrada" 0
    done
}

# ──────────────────────────────────────────────────────────────
# MODO VOZ: wake-word + whisper offline
# ──────────────────────────────────────────────────────────────
bucle_voz() {
    if ! verificar_dependencias_voz; then
        echo "[318] No puedo arrancar el modo voz. Probá el modo texto."
        return 1
    fi

    echo "════════════════════════════════════════"
    echo "  318 · Asistente personal · escuchando (offline)"
    echo "  Decí \"autónomo\" para activar"
    echo "════════════════════════════════════════"

    echo "[DEBUG] Probando el micrófono $DURACION_WAKE seg (decí cualquier cosa)..."
    prueba="$(escuchar "$DURACION_WAKE")"
    if [ -z "$prueba" ]; then
        echo "[AVISO] No se transcribió nada. Revisá permisos si se repite en el loop."
    else
        echo "[DEBUG] Se escuchó: \"$prueba\""
    fi

    local ESTADO="dormido"

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
                    procesar_comando "$comando_incluido" 1
                fi
            fi

        else
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

            procesar_comando "$frase_raw" 1
        fi
    done
}

# ──────────────────────────────────────────────────────────────
# ARRANQUE: elegir voz o texto
# ──────────────────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo "  318 · Ink318 Software"
echo "════════════════════════════════════════"
read -r -p "¿Querés hablar (voz) o escribir (texto)? [voz/texto]: " MODO_ELEGIDO
MODO_ELEGIDO="$(normalizar "$MODO_ELEGIDO")"

if [[ "$MODO_ELEGIDO" == t* ]]; then
    bucle_texto
else
    bucle_voz
fi
