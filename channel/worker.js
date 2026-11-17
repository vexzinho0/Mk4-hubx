// MK4 Channel - canal de telemetria do executor para o agente.
// POST /log?k=KEY   { run, events:[{kind, data}] }
// GET  /runs?k=KEY  lista as sessoes recebidas
// GET  /dump?k=KEY&run=ID&after=0&limit=300  le os eventos
// GET  /clear?k=KEY&run=ID (ou all=1)      apaga

const KEY = "24fd78a1bcc03ad77faf1d6c445b7a6b";
const MAX_EVENTS_PER_POST = 300;
const MAX_BODY = 512 * 1024;

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "*",
  "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...cors },
  });
}

let schemaReady = false;
async function ensureSchema(env) {
  if (schemaReady) return;
  await env.DB.exec(
    "CREATE TABLE IF NOT EXISTS logs (" +
      "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
      "ts TEXT NOT NULL, " +
      "run TEXT NOT NULL, " +
      "kind TEXT NOT NULL, " +
      "payload TEXT NOT NULL)"
  );
  await env.DB.exec("CREATE INDEX IF NOT EXISTS idx_logs_run ON logs(run, id)");
  schemaReady = true;
}

async function handleLog(request, env) {
  const raw = await request.text();
  if (raw.length > MAX_BODY) return json({ ok: false, error: "body grande demais" }, 413);
  let body;
  try {
    body = JSON.parse(raw);
  } catch (e) {
    return json({ ok: false, error: "json invalido" }, 400);
  }
  const run = String(body.run || "sem-run").slice(0, 64);
  const events = Array.isArray(body.events)
    ? body.events
    : body.kind
      ? [{ kind: body.kind, data: body.data }]
      : [];
  if (!events.length) return json({ ok: false, error: "nenhum evento" }, 400);
  if (events.length > MAX_EVENTS_PER_POST) events.length = MAX_EVENTS_PER_POST;

  const ts = new Date().toISOString();
  const statements = events.map((ev) => {
    const kind = String(ev && ev.kind ? ev.kind : "event").slice(0, 48);
    let payload;
    try {
      payload = JSON.stringify(ev && ev.data !== undefined ? ev.data : null);
    } catch (e) {
      payload = JSON.stringify({ erro: "payload nao serializavel" });
    }
    return env.DB.prepare("INSERT INTO logs (ts, run, kind, payload) VALUES (?, ?, ?, ?)").bind(
      ts,
      run,
      kind,
      payload
    );
  });
  await env.DB.batch(statements);
  return json({ ok: true, run, stored: statements.length });
}

async function handleDump(url, env) {
  const run = url.searchParams.get("run");
  const after = Number(url.searchParams.get("after") || 0) || 0;
  let limit = Number(url.searchParams.get("limit") || 300) || 300;
  if (limit > 1000) limit = 1000;
  const stmt = run
    ? env.DB.prepare(
        "SELECT id, ts, run, kind, payload FROM logs WHERE run = ? AND id > ? ORDER BY id LIMIT ?"
      ).bind(run, after, limit)
    : env.DB.prepare("SELECT id, ts, run, kind, payload FROM logs WHERE id > ? ORDER BY id LIMIT ?").bind(
        after,
        limit
      );
  const { results } = await stmt.all();
  const rows = (results || []).map((r) => {
    let data = null;
    try {
      data = JSON.parse(r.payload);
    } catch (e) {
      data = r.payload;
    }
    return { id: r.id, ts: r.ts, run: r.run, kind: r.kind, data };
  });
  return json({ ok: true, count: rows.length, next: rows.length ? rows[rows.length - 1].id : after, rows });
}

async function handleRuns(env) {
  const { results } = await env.DB.prepare(
    "SELECT run, COUNT(*) AS eventos, MIN(ts) AS inicio, MAX(ts) AS fim FROM logs GROUP BY run ORDER BY fim DESC LIMIT 20"
  ).all();
  return json({ ok: true, runs: results || [] });
}

async function handleClear(url, env) {
  const run = url.searchParams.get("run");
  const all = url.searchParams.get("all");
  if (all) await env.DB.exec("DELETE FROM logs");
  else if (run) await env.DB.prepare("DELETE FROM logs WHERE run = ?").bind(run).run();
  else return json({ ok: false, error: "use run=ID ou all=1" }, 400);
  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });
    const key = url.searchParams.get("k") || request.headers.get("x-mk4-key") || "";
    if (key !== KEY) return json({ ok: false, error: "unauthorized" }, 401);
    if (!env.DB) return json({ ok: false, error: "binding DB ausente: rode o deploy depois do storage" }, 503);
    const path = url.pathname.replace(/\/+$/, "");
    try {
      await ensureSchema(env);
      if (path === "" || path === "/") {
        return json({ ok: true, service: "mk4-channel", rotas: ["POST /log", "GET /runs", "GET /dump", "GET /clear"] });
      }
      if (path === "/log" && request.method === "POST") return await handleLog(request, env);
      if (path === "/dump") return await handleDump(url, env);
      if (path === "/runs") return await handleRuns(env);
      if (path === "/clear" && (request.method === "GET" || request.method === "DELETE")) return await handleClear(url, env);
      return json({ ok: false, error: "rota nao encontrada", path }, 404);
    } catch (e) {
      return json({ ok: false, error: String((e && e.stack) || e) }, 500);
    }
  },
};
