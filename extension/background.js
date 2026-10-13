/*
 * Project : Firefox Network Log Recorder
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

"use strict";

const DEFAULTS = {
  recording: false,
  skipStatic: true,
  captureResponseBody: true,
  serverUrl: "http://127.0.0.1:8765",
  site: "",
};

const STATIC_TYPES = new Set([
  "image",
  "imageset",
  "stylesheet",
  "script",
  "font",
  "manifest",
  "web_manifest",
]);

const MAX_STORED = 500;
const MAX_BODY_CHARS = 32768;
const MAX_RESPONSE_CHARS = 131072;
const MAX_HEADER_CHARS = 8192;
const FLUSH_MS = 350;
const PERSIST_MS = 900;

let state = Object.assign({}, DEFAULTS);

const pending = new Map();
let records = [];
let netQueue = [];
let flushTimer = null;
let persistTimer = null;
let dirty = false;

const stats = { captured: 0, skipped: 0, sent: 0, failed: 0, lastError: null };

browser.storage.local
  .get(DEFAULTS)
  .then((stored) => {
    state = {
      recording: stored.recording === true,
      skipStatic: stored.skipStatic !== false,
      captureResponseBody: stored.captureResponseBody !== false,
      serverUrl:
        typeof stored.serverUrl === "string" && stored.serverUrl.trim()
          ? stored.serverUrl.trim()
          : DEFAULTS.serverUrl,
      site: typeof stored.site === "string" ? stored.site : "",
    };
    records = Array.isArray(stored.records) ? stored.records : [];
    updateBadge();
  })
  .catch((err) => console.error("[NLR] init failed", err));

function serverOrigin() {
  try {
    return new URL(state.serverUrl).origin;
  } catch (e) {
    return "http://127.0.0.1:8765";
  }
}

function isOwnUpload(url) {
  return (
    url.startsWith(serverOrigin()) ||
    url.includes("127.0.0.1:8765") ||
    url.includes("localhost:8765")
  );
}

function shouldSkip(details) {
  if (!state.recording) return true;
  if (!/^https?:/i.test(details.url)) return true;
  if (isOwnUpload(details.url)) return true;
  if (
    state.skipStatic &&
    details.method === "GET" &&
    STATIC_TYPES.has(details.type)
  ) {
    stats.skipped++;
    return true;
  }
  return false;
}

function decodeBytes(buf) {
  try {
    return new TextDecoder("utf-8", { fatal: false }).decode(buf);
  } catch (e) {
    try {
      const bytes = new Uint8Array(buf);
      let s = "";
      for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
      return s;
    } catch (e2) {
      return "";
    }
  }
}

function parseRequestBody(rb) {
  if (!rb) return null;
  if (rb.error) return { kind: "error", error: String(rb.error) };
  if (rb.formData) {
    const form = {};
    for (const key of Object.keys(rb.formData)) {
      const vals = rb.formData[key];
      form[key] = Array.isArray(vals) ? vals.map(String) : [String(vals)];
    }
    return { kind: "form", form };
  }
  if (Array.isArray(rb.raw) && rb.raw.length) {
    let text = "";
    for (const chunk of rb.raw) {
      if (chunk && chunk.bytes) text += decodeBytes(chunk.bytes);
      if (text.length > MAX_BODY_CHARS) {
        text = text.slice(0, MAX_BODY_CHARS) + "\u2026[truncated]";
        break;
      }
    }
    return { kind: "raw", text };
  }
  return null;
}

function headersToObject(headers) {
  if (!headers) return null;
  const out = {};
  for (const h of headers) {
    const name = h.name;
    if (!name) continue;
    const value = h.value == null ? "" : String(h.value);
    if (out[name] == null) {
      out[name] = value;
    } else if (!out[name].endsWith("\u2026")) {
      out[name] += ", " + value;
    }
    if (out[name].length > MAX_HEADER_CHARS) {
      out[name] = out[name].slice(0, MAX_HEADER_CHARS) + "\u2026";
    }
  }
  return out;
}

function onBeforeRequest(details) {
  if (shouldSkip(details)) return {};
  const rec = {
    id: details.requestId,
    site: state.site || "",
    url: details.url,
    method: details.method,
    type: details.type,
    tabId: details.tabId,
    timeStamp: details.timeStamp,
    startedAt: new Date(details.timeStamp).toISOString(),
    requestHeaders: null,
    responseHeaders: null,
    requestBody: parseRequestBody(details.requestBody),
    statusCode: null,
    statusLine: null,
    durationMs: null,
    fromCache: false,
    error: null,
    responseBody: null,
    responseTruncated: false,
    _completed: false,
    _filterDone: true,
    _decoder: null,
    _body: "",
  };
  pending.set(details.requestId, rec);
  if (state.captureResponseBody) attachResponseFilter(details.requestId, rec);
  return {};
}

function attachResponseFilter(requestId, rec) {
  let filter;
  try {
    filter = browser.webRequest.filterResponseData(requestId);
  } catch (e) {
    rec._filterDone = true;
    return;
  }

  rec._filterDone = false;
  rec._decoder = new TextDecoder("utf-8", { fatal: false });

  filter.ondata = (event) => {
    try {
      filter.write(event.data);
    } catch (e) {
      /* ignore */
    }
    if (rec._body.length < MAX_RESPONSE_CHARS) {
      try {
        rec._body += rec._decoder.decode(event.data, { stream: true });
      } catch (e) {
        /* ignore */
      }
    } else {
      rec.responseTruncated = true;
    }
  };

  filter.onstop = () => {
    try {
      filter.close();
    } catch (e) {
      /* ignore */
    }
    try {
      rec._body += rec._decoder.decode();
    } catch (e) {
      /* ignore */
    }
    if (rec._body.length > MAX_RESPONSE_CHARS) {
      rec._body = rec._body.slice(0, MAX_RESPONSE_CHARS);
      rec.responseTruncated = true;
    }
    rec.responseBody = rec._body;
    rec._filterDone = true;
    maybeFinalize(rec);
  };

  filter.onerror = () => {
    try {
      filter.close();
    } catch (e) {
      /* ignore */
    }
    rec._filterDone = true;
    maybeFinalize(rec);
  };
}

function maybeFinalize(rec) {
  if (!rec._completed || !rec._filterDone) return;
  finalize(rec);
}

function onBeforeSendHeaders(details) {
  const rec = pending.get(details.requestId);
  if (!rec) return;
  rec.requestHeaders = headersToObject(details.requestHeaders);
}

function onHeadersReceived(details) {
  const rec = pending.get(details.requestId);
  if (!rec) return;
  rec.responseHeaders = headersToObject(details.responseHeaders);
  rec.statusCode = details.statusCode;
  rec.statusLine = details.statusLine;
}

function onCompleted(details) {
  const rec = pending.get(details.requestId);
  if (!rec) return;
  rec.durationMs =
    typeof details.timeStamp === "number"
      ? Math.round(details.timeStamp - rec.timeStamp)
      : null;
  rec.fromCache = details.fromCache === true;
  if (rec.fromCache) rec._filterDone = true;
  rec._completed = true;
  if (!rec._filterDone) {
    setTimeout(() => {
      if (pending.has(rec.id)) {
        rec._filterDone = true;
        maybeFinalize(rec);
      }
    }, 2000);
  }
  maybeFinalize(rec);
}

function onErrorOccurred(details) {
  const rec = pending.get(details.requestId);
  if (!rec) return;
  rec.error = details.error || "unknown error";
  rec.durationMs =
    typeof details.timeStamp === "number"
      ? Math.round(details.timeStamp - rec.timeStamp)
      : null;
  rec._completed = true;
  rec._filterDone = true;
  finalize(rec);
}

function finalize(rec) {
  if (!pending.has(rec.id)) return;
  pending.delete(rec.id);
  delete rec._completed;
  delete rec._filterDone;
  delete rec._decoder;
  delete rec._body;
  stats.captured++;
  records.push(rec);
  if (records.length > MAX_STORED) {
    records.splice(0, records.length - MAX_STORED);
  }
  schedulePersist();
  if (state.recording) {
    netQueue.push(rec);
    scheduleFlush();
  }
}

function scheduleFlush() {
  if (flushTimer) return;
  flushTimer = setTimeout(flush, FLUSH_MS);
}

async function flush() {
  flushTimer = null;
  if (!netQueue.length) return;
  const batch = netQueue.splice(0, netQueue.length);
  const url = state.serverUrl.replace(/\/+$/, "") + "/api/logs";
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(batch),
    });
    if (res.ok) {
      stats.sent += batch.length;
    } else {
      stats.failed += batch.length;
      stats.lastError = "Server responded HTTP " + res.status;
    }
  } catch (err) {
    stats.failed += batch.length;
    stats.lastError = "Cannot reach " + url + " (is the viewer app running?)";
  }
}

function schedulePersist() {
  dirty = true;
  if (persistTimer) return;
  persistTimer = setTimeout(() => {
    persistTimer = null;
    if (!dirty) return;
    dirty = false;
    browser.storage.local.set({ records }).catch(() => {});
  }, PERSIST_MS);
}

function persistSettings() {
  return browser.storage.local
    .set({
      recording: state.recording,
      skipStatic: state.skipStatic,
      captureResponseBody: state.captureResponseBody,
      serverUrl: state.serverUrl,
      site: state.site,
    })
    .catch(() => {});
}

function updateBadge() {
  try {
    browser.browserAction.setBadgeText({
      text: state.recording ? "REC" : "",
    });
    browser.browserAction.setBadgeBackgroundColor({
      color: state.recording ? "#d13438" : "#00000000",
    });
  } catch (e) {
    /* ignore */
  }
}

function snapshot() {
  return {
    recording: state.recording,
    skipStatic: state.skipStatic,
    captureResponseBody: state.captureResponseBody,
    serverUrl: state.serverUrl,
    site: state.site,
    count: records.length,
    stats: Object.assign({}, stats),
  };
}

function setRecording(value) {
  state.recording = !!value;
  if (!state.recording) {
    pending.clear();
    netQueue.length = 0;
    if (flushTimer) {
      clearTimeout(flushTimer);
      flushTimer = null;
    }
  }
  updateBadge();
  return persistSettings().then(snapshot);
}

function clearLogs() {
  records = [];
  pending.clear();
  netQueue.length = 0;
  stats.captured = 0;
  stats.skipped = 0;
  stats.sent = 0;
  stats.failed = 0;
  stats.lastError = null;
  dirty = true;
  schedulePersist();
  const base = serverOrigin();
  fetch(base + "/api/logs", { method: "DELETE" }).catch(() => {});
  return Promise.resolve(snapshot());
}

function resendAll() {
  if (!records.length) return Promise.resolve(snapshot());
  netQueue = records.slice();
  scheduleFlush();
  return Promise.resolve(snapshot());
}

browser.webRequest.onBeforeRequest.addListener(
  onBeforeRequest,
  { urls: ["<all_urls>"] },
  ["blocking", "requestBody"]
);
browser.webRequest.onBeforeSendHeaders.addListener(
  onBeforeSendHeaders,
  { urls: ["<all_urls>"] },
  ["requestHeaders"]
);
browser.webRequest.onHeadersReceived.addListener(
  onHeadersReceived,
  { urls: ["<all_urls>"] },
  ["responseHeaders"]
);
browser.webRequest.onCompleted.addListener(onCompleted, {
  urls: ["<all_urls>"],
});
browser.webRequest.onErrorOccurred.addListener(onErrorOccurred, {
  urls: ["<all_urls>"],
});

browser.runtime.onMessage.addListener((msg) => {
  if (!msg || typeof msg.type !== "string") return undefined;
  switch (msg.type) {
    case "getState":
      return Promise.resolve(snapshot());
    case "setRecording":
      return setRecording(msg.value);
    case "setSkipStatic":
      state.skipStatic = !!msg.value;
      return persistSettings().then(snapshot);
    case "setCaptureResponseBody":
      state.captureResponseBody = !!msg.value;
      return persistSettings().then(snapshot);
    case "setServerUrl": {
      const url = String(msg.value || "").trim();
      state.serverUrl = url || DEFAULTS.serverUrl;
      return persistSettings().then(snapshot);
    }
    case "setSite":
      state.site = String(msg.value || "").trim();
      return persistSettings().then(snapshot);
    case "clear":
      return clearLogs();
    case "getRecords":
      return Promise.resolve(records.slice());
    case "resendAll":
      return resendAll();
    default:
      return undefined;
  }
});
