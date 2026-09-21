#!/data/data/com.termux/files/usr/bin/bash
# publicar_version.sh - Publica una nueva version de CyberIA 318
# © 2026 Pablo Daniel De Luca - Ink318 Software

set -e
B="$HOME/proyectos318"
cd "$B"

echo "══════════════════════════════════════════════"
echo "   ⚡ CYBERIA 318 · Publicar nueva version"
echo "══════════════════════════════════════════════"
echo ""

ULTIMA=$(git tag | sort -V | tail -1)
[ -z "$ULTIMA" ] && ULTIMA="(ninguna)"
echo "Última versión publicada: $ULTIMA"
echo ""

read -p "Nueva versión (ej: v1.1, v2.0): " VERSION
[ -z "$VERSION" ] && { echo "Cancelado."; exit 1; }
read -p "Título (ej: Voz integrada): " TITULO
read -p "Descripción corta: " DESC

echo ""
echo "→ Cambios sin commitear:"
git status --short
echo ""
read -p "¿Continuar? [s/N]: " OK
[[ ! "${OK,,}" == "s" ]] && { echo "Cancelado."; exit 0; }

# Commit + push
echo ""
echo "→ Commit..."
git add -A
git commit -m "⚡ $VERSION · $TITULO

$DESC

© 2026 Pablo Daniel De Luca · Ink318 Software" || echo "(sin cambios)"

echo ""
echo "→ Push a main..."
git push origin main

# Tag + release
echo ""
echo "→ Creando tag y release $VERSION..."

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

git tag -a "$VERSION" -m "$VERSION · $TITULO"
git push origin "$VERSION"

gh release create "$VERSION" \
  "$TARBALL" \
  --title "$VERSION · $TITULO" \
  --notes "## $TITULO

$DESC

### Instalación / Actualización

**Instalación nueva:**
\`\`\`bash
pkg install python jq curl ffmpeg git ollama android-tools termux-api
git clone https://github.com/Pablodluca/cyberia-318.git
cd cyberia-318
ollama pull qwen2.5:1.5b
ollama create cyberia318 -f config/CyberIA318.Modelfile
bash arrancar.sh
\`\`\`

**Actualización (si ya la tenías):**
\`\`\`bash
cd ~/proyectos318
bash actualizar.sh
\`\`\`

© 2026 Pablo Daniel De Luca · Ink318 Software"

echo ""
echo "══════════════════════════════════════════════"
echo "   ✅ $VERSION PUBLICADA"
echo "   https://github.com/Pablodluca/cyberia-318/releases/tag/$VERSION"
echo "══════════════════════════════════════════════"
