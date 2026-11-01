// Cadence Desk: while a focus session from the phone is running, shows it in the status bar and prompts desk breaks
// here, so the phone stays quiet. No VS Code open means you're away from the screen: no prompts anywhere.
// Answers (done / skipped) and active minutes go back to the server; the app reads them.
const vscode = require("vscode");

let bar, poll, breakTimer, focus = null, lastEyes = 0, lastStand = 0, activeMinutes = 0, lastActivity = Date.now();

function settings() {
  const c = vscode.workspace.getConfiguration("cadence");
  return { server: (c.get("server") || "").replace(/\/+$/, ""), eyes: c.get("eyesEvery") || 20, stand: c.get("standEvery") || 50 };
}

// On a machine with ~/.cadence-server (url= and token= lines), no setup is needed
function localFile() {
  try {
    const text = require("fs").readFileSync(require("path").join(require("os").homedir(), ".cadence-server"), "utf8");
    const get = (k) => (text.match(new RegExp("^" + k + "=(.*)$", "m")) || [])[1]?.trim();
    return { server: get("url"), token: get("token") };
  } catch {
    return {};
  }
}

async function call(context, body) {
  const file = localFile();
  const server = settings().server || (file.server || "").replace(/\/+$/, "");
  const token = (await context.secrets.get("cadence.token")) || file.token;
  if (!server || !token) return null;
  try {
    const res = await fetch(server + "/focus.php", {
      method: body ? "POST" : "GET",
      headers: { "X-Cadence-Token": token, "Authorization": "Bearer " + token, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  }
}

function show() {
  if (!focus) { bar.hide(); return; }
  const left = Math.round((focus.end - Date.now()) / 60000);
  bar.text = left >= 0 ? `$(target) ${focus.title} · ${left} min left` : `$(flame) ${focus.title} · +${-left} min in flow`;
  bar.tooltip = "Cadence focus session (from your phone)";
  bar.show();
}

async function prompt(context, kind) {
  const text = kind === "eyes" ? "20-20-20: look at something 6 m away for 20 seconds." : "Stand up, stretch, walk for two minutes.";
  const answer = await vscode.window.showInformationMessage(`Cadence · ${text}`, "Done", "Skip");
  await call(context, { event: { kind, answer: answer === "Done" ? "done" : "skipped", at: Date.now() } });
}

async function refresh(context) {
  const state = await call(context);
  if (!state) return;
  const was = focus;
  focus = state.focus && state.focus.end ? state.focus : null;
  if (focus && (!was || was.start !== focus.start)) { lastEyes = lastStand = Date.now(); }
  show();
}

function tick(context) {
  show();
  if (!focus || !vscode.window.state.focused) return;
  const { eyes, stand } = settings();
  const now = Date.now();
  if (now - lastStand >= stand * 60000) { lastStand = lastEyes = now; prompt(context, "stand"); }
  else if (now - lastEyes >= eyes * 60000) { lastEyes = now; prompt(context, "eyes"); }
}

function activate(context) {
  bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  context.subscriptions.push(bar);
  context.subscriptions.push(vscode.commands.registerCommand("cadence.setToken", async () => {
    const token = await vscode.window.showInputBox({ prompt: "Cadence server token", password: true, ignoreFocusOut: true });
    if (token) { await context.secrets.store("cadence.token", token.trim()); refresh(context); }
  }));
  context.subscriptions.push(vscode.commands.registerCommand("cadence.refresh", () => refresh(context)));
  // Active minutes: any edit or selection in the last 2 minutes counts
  const touch = () => { lastActivity = Date.now(); };
  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument(touch), vscode.window.onDidChangeTextEditorSelection(touch));
  const minute = setInterval(async () => {
    if (vscode.window.state.focused && Date.now() - lastActivity < 120000) activeMinutes++;
    if (activeMinutes >= 15) { const m = activeMinutes; activeMinutes = 0; await call(context, { event: { kind: "active", answer: "", minutes: m, at: Date.now() } }); }
  }, 60000);
  poll = setInterval(() => refresh(context), 30000);
  breakTimer = setInterval(() => tick(context), 15000);
  context.subscriptions.push({ dispose: () => { clearInterval(poll); clearInterval(breakTimer); clearInterval(minute); } });
  refresh(context);
}

function deactivate() {}

module.exports = { activate, deactivate };
