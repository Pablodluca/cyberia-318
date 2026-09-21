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
