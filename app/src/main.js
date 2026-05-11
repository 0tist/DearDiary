// Tauri 2 with `withGlobalTauri: true` exposes `window.__TAURI__.core.invoke`.
const invoke = window.__TAURI__?.core?.invoke;

const entry = document.getElementById("entry");
const saveBtn = document.getElementById("save");
const processBtn = document.getElementById("process");
const statusEl = document.getElementById("status");

function fmtTime(d) {
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function setStatus(msg) {
  statusEl.textContent = msg;
}

async function save() {
  const text = entry.value;
  if (!text.trim()) return;
  if (!invoke) {
    setStatus("error: tauri bridge missing");
    return;
  }
  saveBtn.disabled = true;
  try {
    await invoke("save_entry", { text });
    entry.value = "";
    setStatus(`saved ${fmtTime(new Date())}`);
  } catch (e) {
    setStatus(`error: ${e}`);
  } finally {
    saveBtn.disabled = false;
    entry.focus();
  }
}

async function processNow() {
  if (!invoke) return;
  processBtn.disabled = true;
  try {
    await invoke("process_now");
    setStatus("processing…");
  } catch (e) {
    setStatus(`error: ${e}`);
  } finally {
    processBtn.disabled = false;
  }
}

saveBtn.addEventListener("click", save);
processBtn.addEventListener("click", processNow);
entry.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
    e.preventDefault();
    save();
  }
});
