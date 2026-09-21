#!/data/data/com.termux/files/usr/bin/bash
# conectar_adb.sh - Conecta Termux con ADB inalámbrico
# © 2026 Pablo Daniel De Luca - Ink318 Software

echo "═══ Conexión ADB Inalámbrica ═══"
echo ""
echo "En el celu: Ajustes → Opciones de desarrollador →"
echo "  Depuración inalámbrica → 'Emparejar dispositivo con código'"
echo ""
read -p "IP:Puerto de EMPAREJAMIENTO (ej: 192.168.1.42:37891): " PAIR
read -p "Código de 6 dígitos: " CODE

echo ""
echo "→ Emparejando con $PAIR ..."
adb pair "$PAIR" "$CODE"

if [ $? -ne 0 ]; then
    echo "✗ Falló el emparejamiento. Revisá IP/puerto/código."
    exit 1
fi

echo "✓ Emparejado. Ahora conectando al puerto principal..."
echo ""
echo "En el celu, tocá 'Depuración inalámbrica' de nuevo para ver:"
echo "  IP:Puerto (ej: 192.168.1.42:41235)"
echo ""
read -p "IP:Puerto de CONEXIÓN: " CONN

adb connect "$CONN"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Conectado a $CONN"
    echo ""
    echo "Test rápido:"
    adb shell echo "Hola desde CyberIA 318"
    adb shell getprop ro.product.model
    echo ""
    echo "════════════════════════════════════════"
    echo "  ✅ ADB LISTO. Ahora CyberIA controla el celu."
    echo "════════════════════════════════════════"
else
    echo "✗ Falló la conexión."
fi
