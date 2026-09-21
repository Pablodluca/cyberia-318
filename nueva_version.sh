#!/data/data/com.termux/files/usr/bin/bash
# nueva_version.sh - Publica una nueva versión de CyberIA 318
# © 2026 Pablo Daniel De Luca - Ink318 Software

set -e
B="$HOME/proyectos318"
cd "$B"

echo "════════════════════════════════════════════════════════════"
echo "   ⚡ CYBERIA 318 · Nueva Versión"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Última versión publicada ──
ULTIMA=$(git tag | sort -V | tail -1)
[ -z "$ULTIMA" ] && ULTIMA="(ninguna)"
echo "Última versión: $ULTIMA"
echo ""

# ── Pedir datos ──
read -p "Nueva versión (ej: v1.1, v1.2, v2.0): " VERSION
[ -z "$VERSION" ] && { echo "Cancelado."; exit 1; }

read -p "Título corto (ej: 'Voz integrada'): " TITULO
read -p "Descripción (una línea): " DESC

echo ""
echo "→ Cambios sin commitear:"
git status --short

echo ""
read -p "¿Continuar? [s/N]: " OK
[[ ! "${OK,,}" == "s" ]] && { echo "Cancelado."; exit 0; }

# ── Commit ──
echo ""
echo "→ Haciendo commit..."
git add -A
git commit -m "⚡ $VERSION · $TITULO

$DESC

© 2026 Pablo Daniel De Luca · Ink318 Software" || echo "(Sin cambios para commitear)"

# ── Push ──
echo ""
echo "→ Pusheando a GitHub..."
git push origin main

# ── Tag ──
echo ""
echo "→ Creando tag $VERSION..."
git tag -a "$VERSION" -m "$VERSION · $TITULO"
git push origin "$VERSION"

# ── Release ──
echo ""
echo "→ Creando release en GitHub..."

# Empaquetar distribuble (sin modelos, sin logs, sin basura)
TARBALL="$HOME/cyberia-318-$VERSION.tar.gz"
tar -czf "$TARBALL" \
  --exclude='.git' \
  --exclude='logs' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='*.gguf' \
  --exclude='*.bin' \
  --exclude='_variantes_viejas' \
  -C "$HOME" proyectos318

gh release create "$VERSION" \
  "$TARBALL" \
  --title "$VERSION · $TITULO" \
  --notes "## $TITULO

$DESC

### Qué incluye
- \`router.py\` · texto natural → JSON
- \`ejecutor.py\` · 24 acciones (ADB + filesystem + hardware)
- \`bridge.py\` · servidor HTTP local para la PWA
- \`web/\` · interfaz CyberIA 318
- \`config/\` · commands.json, seguridad.json, Modelfile
- \`manifiesto_cyberia_final.txt\`

### Instalación
\`\`\`bash
pkg install python jq curl ffmpeg git ollama android-tools termux-api
git clone https://github.com/Pablodluca/cyberia-318.git
cd cyberia-318
ollama pull qwen2.5:1.5b
ollama create cyberia318 -f config/CyberIA318.Modelfile
bash arrancar.sh
\`\`\`

© 2026 Pablo Daniel De Luca · Ink318 Software"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "   ✅ $VERSION PUBLICADA"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "   https://github.com/Pablodluca/cyberia-318/releases/tag/$VERSION"
echo ""
