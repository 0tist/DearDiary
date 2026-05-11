// Tauri 2 with `withGlobalTauri: true` exposes `window.__TAURI__.core.invoke`.
const invoke = window.__TAURI__?.core?.invoke;

const entry = document.getElementById("entry");
const saveBtn = document.getElementById("save");
const processBtn = document.getElementById("process");
const statusEl = document.getElementById("status");

let lastSaveTs = null;
let inboxCount = 0;

function fmtTime(d) {
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function renderStatus(msg) {
  const parts = [];
  if (msg) parts.push(msg);
  if (lastSaveTs) parts.push(`saved ${fmtTime(lastSaveTs)}`);
  parts.push(`inbox: ${inboxCount}`);
  statusEl.textContent = parts.join(" · ");
}

async function refreshCount() {
  if (!invoke) return;
  try {
    inboxCount = await invoke("inbox_count");
  } catch (_) {
    /* ignore */
  }
  renderStatus();
}

async function save() {
  const text = entry.value;
  if (!text.trim()) return;
  if (!invoke) {
    renderStatus("error: tauri bridge missing");
    return;
  }
  saveBtn.disabled = true;
  try {
    await invoke("save_entry", { text });
    entry.value = "";
    lastSaveTs = new Date();
    await refreshCount();
  } catch (e) {
    renderStatus(`error: ${e}`);
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
    renderStatus("processing…");
    // Refresh after a beat — Phase B is async; Claude takes seconds to minutes
    setTimeout(refreshCount, 5000);
  } catch (e) {
    renderStatus(`error: ${e}`);
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

// Initial paint + periodic refresh of inbox count
refreshCount();
setInterval(refreshCount, 30000);
