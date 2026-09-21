// © 2026 Pablo Daniel De Luca - Ink318 Software
const API = location.origin + "/api";
const $ = (id) => document.getElementById(id);
const messages = $("messages");
const prompt = $("prompt");
const sendBtn = $("sendBtn");
const statusText = $("statusText");
const coreSphere = $("coreSphere");
const modelSelect = $("modelSelect");
const settingsModal = $("settingsModal");
const systemInfo = $("systemInfo");

let currentModel = null;
let busy = false;

// ─── Init ───
async function init() {
  try {
    const r = await fetch(`${API}/health`);
    if (!r.ok) throw new Error();
    statusText.textContent = "en línea · local";
    coreSphere.classList.add("online");
  } catch {
    statusText.textContent = "sin conexión al motor";
    return;
  }
  loadModels();
  loadSystem();
}

async function loadModels() {
  try {
    const r = await fetch(`${API}/models`);
    const d = await r.json();
    const models = (d.models || []).map((m) => m.name);
    modelSelect.innerHTML = "";
    models.forEach((name) => {
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      modelSelect.appendChild(opt);
    });
    const pref = models.find((m) => m.startsWith("cyberia318")) || models[0];
    if (pref) {
      modelSelect.value = pref;
      currentModel = pref;
    }
  } catch (e) {
    console.warn("No se pudieron cargar modelos", e);
  }
}

async function loadSystem() {
  try {
    const r = await fetch(`${API}/system`);
    const d = await r.json();
    systemInfo.innerHTML = `
      <div><b>Arq:</b> ${d.kernel || "?"}</div>
      <div><b>RAM:</b> ${d.ram_free_mb} / ${d.ram_total_mb} MB libres</div>
      <div><b>Batería:</b> ${d.battery}% (${d.battery_status})</div>
    `;
  } catch {}
}

// ─── Chat ───
function addMsg(role, text) {
  const div = document.createElement("div");
  div.className = `msg ${role}`;
  div.textContent = text;
  messages.appendChild(div);
  messages.scrollTop = messages.scrollHeight;
  return div;
}

async function sendMessage(text) {
  if (busy) return;
  text = (text || "").trim();
  if (!text) return;
  busy = true;
  sendBtn.disabled = true;
  coreSphere.classList.add("thinking");

  addMsg("user", text);
  prompt.value = "";
  prompt.style.height = "auto";

  const loading = addMsg("ai", "▋ pensando...");

  try {
    const r = await fetch(`${API}/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: text, model: currentModel }),
    });
    const d = await r.json();

    if (d.error) {
      loading.textContent = `⚠ ${d.error}`;
    } else if (d.type === "chat") {
      loading.textContent = d.response || "(sin respuesta)";
    } else if (d.type === "action") {
      const sal = d.result?.salida || JSON.stringify(d.result);
      loading.textContent = `✓ ${sal}`;
    } else if (d.type === "confirm") {
      loading.textContent = `⚠ ${d.pregunta} (escribí "sí" para confirmar)`;
    } else {
      loading.textContent = JSON.stringify(d);
    }
  } catch (e) {
    loading.textContent = `⚠ Error de red: ${e.message}`;
  } finally {
    busy = false;
    sendBtn.disabled = false;
    coreSphere.classList.remove("thinking");
    messages.scrollTop = messages.scrollHeight;
  }
}

// ─── Eventos ───
sendBtn.addEventListener("click", () => sendMessage(prompt.value));
prompt.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    sendMessage(prompt.value);
  }
});
prompt.addEventListener("input", () => {
  prompt.style.height = "auto";
  prompt.style.height = Math.min(prompt.scrollHeight, 120) + "px";
});

window.quick = (t) => sendMessage(t);
window.closeSettings = () => settingsModal.classList.remove("open");
$("settingsBtn").addEventListener("click", () => {
  settingsModal.classList.add("open");
  loadSystem();
});
modelSelect.addEventListener("change", async () => {
  currentModel = modelSelect.value;
  await fetch(`${API}/model`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: currentModel }),
  });
});

init();
