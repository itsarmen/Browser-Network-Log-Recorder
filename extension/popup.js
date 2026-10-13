/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

"use strict";

const $ = (id) => document.getElementById(id);

const el = {
  conn: $("conn"),
  recording: $("recording"),
  recHint: $("recHint"),
  skipStatic: $("skipStatic"),
  captureResponseBody: $("captureResponseBody"),
  site: $("site"),
  serverUrl: $("serverUrl"),
  saveUrl: $("saveUrl"),
  count: $("count"),
  captured: $("captured"),
  skipped: $("skipped"),
  sent: $("sent"),
  failed: $("failed"),
  error: $("error"),
  resend: $("resend"),
  exportBtn: $("export"),
  clear: $("clear"),
};

function send(type, extra) {
  return browser.runtime.sendMessage(Object.assign({ type }, extra || {}));
}

function render(state) {
  if (!state) return;
  el.recording.checked = !!state.recording;
  el.skipStatic.checked = !!state.skipStatic;
  el.captureResponseBody.checked = state.captureResponseBody !== false;
  if (document.activeElement !== el.site) {
    el.site.value = state.site || "";
  }
  if (document.activeElement !== el.serverUrl) {
    el.serverUrl.value = state.serverUrl || "";
  }
  el.count.textContent = state.count ?? 0;
  el.captured.textContent = state.stats?.captured ?? 0;
  el.skipped.textContent = state.stats?.skipped ?? 0;
  el.sent.textContent = state.stats?.sent ?? 0;
  el.failed.textContent = state.stats?.failed ?? 0;

  el.recHint.textContent = state.recording
    ? "On — capturing requests now."
    : "Off — requests are not captured.";

  const err = state.stats?.lastError;
  if (err) {
    el.error.textContent = err;
    el.error.classList.remove("hidden");
  } else {
    el.error.classList.add("hidden");
  }
}

async function refresh() {
  try {
    render(await send("getState"));
  } catch (e) {
    /* ignore */
  }
}

async function checkConnection() {
  let url = el.serverUrl.value.trim() || "http://127.0.0.1:8765";
  url = url.replace(/\/+$/, "") + "/api/ping";
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 1200);
  try {
    const res = await fetch(url, { signal: controller.signal, cache: "no-store" });
    if (res.ok) {
      el.conn.textContent = "viewer online";
      el.conn.className = "pill on";
    } else {
      el.conn.textContent = "viewer error";
      el.conn.className = "pill off";
    }
  } catch (e) {
    el.conn.textContent = "viewer offline";
    el.conn.className = "pill off";
  } finally {
    clearTimeout(timer);
  }
}

el.recording.addEventListener("change", async () => {
  render(await send("setRecording", { value: el.recording.checked }));
});

el.skipStatic.addEventListener("change", async () => {
  render(await send("setSkipStatic", { value: el.skipStatic.checked }));
});

el.captureResponseBody.addEventListener("change", async () => {
  render(await send("setCaptureResponseBody", { value: el.captureResponseBody.checked }));
});

el.site.addEventListener("change", async () => {
  render(await send("setSite", { value: el.site.value }));
});

el.site.addEventListener("keydown", (e) => {
  if (e.key === "Enter") el.site.blur();
});

el.saveUrl.addEventListener("click", async () => {
  render(await send("setServerUrl", { value: el.serverUrl.value }));
  checkConnection();
});

el.serverUrl.addEventListener("keydown", (e) => {
  if (e.key === "Enter") el.saveUrl.click();
});

el.clear.addEventListener("click", async () => {
  if (!confirm("Clear all stored records (extension and viewer)?")) return;
  render(await send("clear"));
});

el.resend.addEventListener("click", async () => {
  render(await send("resendAll"));
  setTimeout(checkConnection, 500);
});

el.exportBtn.addEventListener("click", async () => {
  const records = await send("getRecords");
  const blob = new Blob([JSON.stringify(records, null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  a.href = url;
  a.download = `network-log-${stamp}.json`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
});

let poll = null;

async function init() {
  await refresh();
  checkConnection();
  poll = setInterval(refresh, 1000);
}

window.addEventListener("unload", () => {
  if (poll) clearInterval(poll);
});

init();
