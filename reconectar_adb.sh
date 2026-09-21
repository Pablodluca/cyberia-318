#!/data/data/com.termux/files/usr/bin/bash
# reconectar_adb.sh - Reconecta ADB por localhost
# © 2026 Pablo Daniel De Luca - Ink318 Software

PORT_FILE="$HOME/.cyberia_adb_port"

# 1. Desconectar todo
adb disconnect >/dev/null 2>&1

# 2. Leer puerto guardado o pedirlo
if [ -f "$PORT_FILE" ]; then
    PORT=$(cat "$PORT_FILE")
    echo "Usando puerto guardado: $PORT"
else
    echo "Puerto no guardado. Buscá en:"
    echo "  Ajustes → Opciones de desarrollador → Depuración inalámbrica"
    echo "  (el puerto de 'Conexión', NO el de emparejamiento)"
    read -p "Puerto: " PORT
    echo "$PORT" > "$PORT_FILE"
fi

# 3. Conectar por localhost
adb connect 127.0.0.1:$PORT

# 4. Verificar
if adb shell getprop ro.product.model 2>/dev/null; then
    echo "✅ ADB localhost OK en puerto $PORT"
else
    echo "❌ Falló. Actualizá el puerto: rm $PORT_FILE && bash $0"
    exit 1
fi
