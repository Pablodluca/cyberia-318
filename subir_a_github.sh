#!/data/data/com.termux/files/usr/bin/bash
# subir_a_github.sh - Publica CyberIA 318 en GitHub
# © 2026 Pablo Daniel De Luca - Ink318 Software

set -e
B="$HOME/proyectos318"
cd "$B"

REPO_NAME="cyberia-318"
REPO_DESC="CyberIA 318 · Asistente personal 100% local · Sin nube, sin telemetría"
REPO_VISIBILITY="public"
GIT_USER_NAME="Pablo Daniel De Luca"
GIT_USER_EMAIL="dress318@gmail.com"

echo "═══ CyberIA 318 · Publicación a GitHub ═══"

cat > .gitignore << 'EOF'
*.gguf
*.bin
*.onnx
*.pt
models/
whisper.cpp/
logs/
*.log
__pycache__/
*.py[cod]
.venv/
venv/
node_modules/
config/config.json
config/*.secret
.env
config/memoria_cyberia.json
*_backup_*
*.bak_*
Cyberia_work/
Cyberia_extraido/
backups/
.DS_Store
*.swp
.vscode/
EOF

YEAR=$(date +%Y)
cat > LICENSE << EOF
COPYRIGHT (c) $YEAR PABLO DANIEL DE LUCA · INK318 SOFTWARE
Todos los derechos reservados.

DNI: 31.649.936 - Email: dress318@gmail.com
Proyecto: CyberIA 318 (Autónomo 3.18)

Este software es propiedad exclusiva de Pablo Daniel De Luca.
Prohibida su reproducción, distribución o uso comercial sin autorización.

El acceso público se otorga solo con fines de visualización y estudio.
NO constituye licencia de uso.

Contacto: dress318@gmail.com
EOF

cat > README.md << 'EOF'
# ⚡ CYBERIA 318

### Asistente personal 100% local · Sin nube · Sin telemetría

**© 2026 Pablo Daniel De Luca · Ink318 Software**

---

## Qué es

CyberIA 318 es un agente autónomo de lenguaje natural que corre completamente dentro de un teléfono Android, sin root, sin servidores externos, sin APIs de nube.

No es un chatbot. Es un simbionte digital con:

- 🧠 LLM local (Ollama + Qwen2.5)
- 👁️ Visión del sistema (filesystem, apps, hardware)
- 🗣️ Voz bidireccional (Whisper.cpp + TTS Android)
- 🛡️ Pensamiento crítico (inhibe órdenes destructivas)
- 🧬 Memoria evolutiva
- 🎨 Interfaz PWA instalable (sin APK, sin Play Store)

## Los 4 pilares

1. **Soberanía absoluta** - Dueño total de tu IA. Sin suscripciones.
2. **Omnipotencia privada** - Acceso total al hardware. Sin restricciones.
3. **Lealtad incondicional** - Diseñada para proteger al individuo.
4. **Evolución consciente** - Aprende y crece con el usuario.

> Podés poner el celular en modo avión. CyberIA sigue funcionando.

## Instalación

```bash
pkg update && pkg upgrade -y
pkg install -y python jq curl ffmpeg git ollama termux-api
git clone https://github.com/Pablodluca/cyberia-318.git
cd cyberia-318
ollama pull qwen2.5:1.5b
ollama create cyberia318 -f config/CyberIA318.Modelfile
bash arrancar.sh
