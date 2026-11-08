// Black-box contract test for the MCP endpoint, speaking the protocol the way an
// agent does (Streamable HTTP, protocol 2025-06-18): initialize -> initialized ->
// tools/list -> tools/call. Hits real Open-Meteo through the app, so it needs network.
//
//   node test/mcp-contract-test.mjs                                   # local runtime, :8081
//   MCP_URL=https://mule-demo.matheusribeiro.dev.br/mcp node test/mcp-contract-test.mjs
//
// No dependencies (Node 18+ fetch).
const URL_MCP = process.env.MCP_URL || "http://localhost:8081/mcp";
const HEADERS = { "Content-Type": "application/json", Accept: "application/json, text/event-stream" };
let sessionId = null;
let nextId = 1;
let failures = 0;

function check(cond, msg) {
  console.log(`${cond ? "ok  " : "FAIL"} ${msg}`);
  if (!cond) failures++;
}

// Responses may come back as plain JSON or as an SSE stream ("data: {...}").
async function readRpc(res) {
  const body = await res.text();
  const json = body.trim().startsWith("{")
    ? body
    : body.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).pop();
  return json ? JSON.parse(json) : null;
}

async function rpc(method, params, { notification = false } = {}) {
  const msg = { jsonrpc: "2.0", method, ...(params ? { params } : {}), ...(notification ? {} : { id: nextId++ }) };
  const res = await fetch(URL_MCP, {
    method: "POST",
    headers: { ...HEADERS, ...(sessionId ? { "Mcp-Session-Id": sessionId } : {}) },
    body: JSON.stringify(msg),
  });
  if (!sessionId) sessionId = res.headers.get("mcp-session-id");
  return { status: res.status, body: notification ? null : await readRpc(res) };
}

const callTool = async (name, args) => (await rpc("tools/call", { name, arguments: args })).body.result;
const toolJson = (result) => JSON.parse(result.content[0].text);

console.log(`MCP contract test against ${URL_MCP}\n`);

const init = await rpc("initialize", {
  protocolVersion: "2025-06-18",
  capabilities: {},
  clientInfo: { name: "mcp-contract-test", version: "1.0.0" },
});
check(init.status === 200 && init.body?.result?.serverInfo?.name === "mule-weather-api", "initialize: server identifies as mule-weather-api");
check(Boolean(sessionId), "initialize: returns an Mcp-Session-Id");
check(Boolean(init.body?.result?.capabilities?.tools), "initialize: advertises the tools capability");

const initialized = await rpc("notifications/initialized", null, { notification: true });
check(initialized.status === 202, "notifications/initialized: accepted (202)");

const list = (await rpc("tools/list")).body.result.tools;
const names = list.map((t) => t.name).sort();
check(JSON.stringify(names) === JSON.stringify(["compare_cities_weather", "get_city_weather"]), `tools/list: exactly the two tools (${names.join(", ")})`);
check(list.every((t) => t.description && t.inputSchema?.required?.length), "tools/list: every tool has a description and required arguments");

const one = await callTool("get_city_weather", { city: "Indaiatuba" });
const reading = one.isError ? null : toolJson(one);
check(one.isError === false && typeof reading?.temperatureCelsius === "number", "get_city_weather: returns a numeric temperature");
check(reading?.description?.pt && reading?.description?.en, "get_city_weather: PT/EN description");

const missing = await callTool("get_city_weather", { city: "Xyzqwertyuiop" });
check(missing.isError === true && /not found/i.test(missing.content[0].text), "get_city_weather: unknown city is a tool error with a readable sentence");

const two = await callTool("compare_cities_weather", { cities: ["Indaiatuba", "Campinas"] });
const results = two.isError ? [] : toolJson(two).results;
check(results.length === 2 && results.every((r) => r.ok), "compare_cities_weather: both cities resolved");

const partial = await callTool("compare_cities_weather", { cities: ["Indaiatuba", "Xyzqwertyuiop"] });
const pr = partial.isError ? [] : toolJson(partial).results;
check(pr.length === 2 && pr[0].ok && !pr[1].ok && pr[1].error === "CITY_NOT_FOUND", "compare_cities_weather: one bad city does not fail the other");

const tooFew = await callTool("compare_cities_weather", { cities: ["Indaiatuba"] });
check(tooFew?.isError === true || tooFew === undefined, "compare_cities_weather: a single city is rejected");

console.log(`\n${failures ? `${failures} check(s) FAILED` : "all checks passed"}`);
process.exit(failures ? 1 : 0);
