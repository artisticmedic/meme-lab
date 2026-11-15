enum PickerPage {
    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Meme Lab</title>
<style>
  :root { color-scheme: light dark; --label: #111; --secondary: rgba(17,17,17,.56); --hair: rgba(17,17,17,.12); --fill: rgba(17,17,17,.05); --hover: rgba(17,17,17,.09); --bg: #f6f6f7; --card: #fff; --on-label: #fff; }
  @media (prefers-color-scheme: dark) { :root { --label: #f2f2f3; --secondary: rgba(242,242,243,.58); --hair: rgba(242,242,243,.14); --fill: rgba(242,242,243,.07); --hover: rgba(242,242,243,.12); --bg: #19191b; --card: #232326; --on-label: #111; } }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.4 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; color: var(--label); background: var(--bg); }
  header { position: sticky; top: 0; z-index: 2; background: color-mix(in srgb, var(--bg) 88%, transparent); backdrop-filter: blur(20px); border-bottom: 1px solid var(--hair); padding: 14px 24px 12px; }
  .title { display: flex; align-items: baseline; gap: 12px; }
  h1 { font-size: 17px; font-weight: 600; margin: 0; }
  #status { color: var(--secondary); font-size: 14px; }
  #error { font-size: 14px; font-weight: 600; }
  .controls { display: flex; gap: 10px; align-items: center; margin-top: 10px; flex-wrap: wrap; }
  #search { flex: 1; min-width: 220px; max-width: 460px; height: 36px; border: 0; border-radius: 10px; background: var(--fill); color: var(--label); padding: 0 12px; font: inherit; outline: none; }
  #search:focus { box-shadow: 0 0 0 2px var(--label); }
  .tabs { display: flex; gap: 4px; }
  .tab { height: 32px; padding: 0 12px; border-radius: 99px; border: 0; background: transparent; color: var(--secondary); font: inherit; font-size: 14px; cursor: pointer; }
  .tab.on { background: var(--label); color: var(--on-label); }
  main { padding: 18px 24px 160px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 12px; }
  .grid.big { grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); }
  .tile { position: relative; border-radius: 12px; padding: 6px; cursor: pointer; border: 0; background: none; text-align: left; color: inherit; font: inherit; }
  .tile:hover, .tile:focus-visible { background: var(--hover); outline: none; }
  .tile.sel { background: var(--hover); box-shadow: inset 0 0 0 2px var(--label); }
  .thumb { position: relative; aspect-ratio: 4/3; border-radius: 8px; overflow: hidden; background: var(--fill); display: grid; place-items: center; }
  .thumb img, .thumb video { width: 100%; height: 100%; object-fit: contain; display: block; }
  .badge { position: absolute; top: 6px; right: 6px; min-width: 24px; height: 24px; border-radius: 12px; background: var(--label); color: var(--on-label); font-size: 13px; font-weight: 600; display: none; place-items: center; padding: 0 7px; }
  .tile.sel .badge, .num .badge { display: grid; }
  .num .badge { left: 6px; right: auto; }
  .info { position: absolute; bottom: 6px; right: 6px; width: 34px; height: 34px; border-radius: 17px; border: 0; background: color-mix(in srgb, var(--card) 85%, transparent); color: var(--label); font-size: 15px; cursor: pointer; opacity: 0; }
  .tile:hover .info, .tile:focus-visible .info { opacity: 1; }
  .name { font-size: 14px; padding: 6px 2px 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .sub { font-size: 13px; color: var(--secondary); padding: 0 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .empty { color: var(--secondary); padding: 40px 0; }
  footer { position: fixed; left: 0; right: 0; bottom: 0; z-index: 3; background: color-mix(in srgb, var(--card) 92%, transparent); backdrop-filter: blur(20px); border-top: 1px solid var(--hair); padding: 12px 24px; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
  .chips { display: flex; gap: 6px; flex-wrap: wrap; flex: 1; min-width: 200px; }
  .chip { display: flex; align-items: center; gap: 6px; height: 34px; padding: 0 6px 0 12px; border-radius: 17px; background: var(--fill); font-size: 14px; }
  .chip button { width: 26px; height: 26px; border-radius: 13px; border: 0; background: transparent; color: var(--secondary); cursor: pointer; font-size: 15px; }
  #idea, #note { height: 38px; min-width: 240px; flex: 1; border: 0; border-radius: 10px; background: var(--fill); color: var(--label); padding: 0 12px; font: inherit; outline: none; }
  .pill { height: 38px; padding: 0 18px; border-radius: 19px; border: 0; background: var(--fill); color: var(--label); font: inherit; font-weight: 500; cursor: pointer; box-shadow: inset 0 0 0 1px var(--hair); }
  .pill.primary { background: var(--label); color: var(--on-label); box-shadow: none; }
  .pill:disabled { opacity: .4; cursor: default; }
  dialog { border: 0; border-radius: 16px; padding: 0; width: min(760px, 92vw); background: var(--card); color: var(--label); box-shadow: 0 20px 60px rgba(0,0,0,.3); }
  dialog::backdrop { background: rgba(0,0,0,.35); }
  .detail { display: grid; grid-template-columns: 1.3fr 1fr; gap: 18px; padding: 18px; }
  .detail .thumb { aspect-ratio: auto; min-height: 240px; }
  .detail h2 { font-size: 17px; margin: 0 0 8px; }
  .detail p { margin: 0 0 8px; color: var(--secondary); font-size: 14px; }
  .detail p b { color: var(--label); font-weight: 500; }
  .rights { display: inline-block; padding: 3px 10px; border-radius: 99px; box-shadow: inset 0 0 0 1px var(--label); font-size: 13px; margin: 4px 0 12px; }
  .row { display: flex; gap: 8px; }
  .done { max-width: 520px; margin: 18vh auto; text-align: center; }
  .done h2 { font-size: 20px; margin: 0 0 8px; }
  .done p { color: var(--secondary); }
</style>
</head>
<body>
<header>
  <div class="title"><h1>Meme Lab</h1><span id="status">Loading…</span><span id="error" role="alert"></span></div>
  <div class="controls" id="controls">
    <input id="search" type="search" placeholder="Search by name or feeling" autocomplete="off" aria-label="Search">
    <div class="tabs" id="tabs"></div>
  </div>
</header>
<main><div class="grid" id="grid"></div></main>
<footer id="footer"></footer>
<dialog id="dialog"></dialog>
<script>
const token = new URLSearchParams(location.search).get("t");
const el = (tag, props = {}, ...children) => { const n = document.createElement(tag); for (const [k, v] of Object.entries(props)) { if (k === "class") n.className = v; else if (k.startsWith("on")) n.addEventListener(k.slice(2), v); else if (v !== undefined && v !== null) n.setAttribute(k, v); } for (const c of children) if (c !== null && c !== undefined) n.append(c); return n; };
let state, selected = [], saved = [], saving = Promise.resolve(), tab = "all", query = "";
const tabs = [["all", "All"], ["template", "Templates"], ["clip", "Clips"], ["made", "Made"], ["rising", "New and rising"]];

async function api(path, body) {
  const res = await fetch(path, body ? { method: "POST", headers: { "Content-Type": "application/json", "X-Meme-Token": token }, body: JSON.stringify(body) } : { headers: { "X-Meme-Token": token } });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

function words(text) { return (text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ']/g, "").split(/[^a-z0-9]+/).filter(Boolean); }
function score(item, terms) {
  const fields = [[5, words(item.title + " " + item.id)], [4, item.tags.flatMap(words)], [3, words(item.vibe)], [2, words(item.howUsed)]];
  let total = 0, hit = 0;
  for (const t of terms) { let best = 0; for (const [w, toks] of fields) { if (toks.includes(t)) best = Math.max(best, w); else if (t.length >= 3 && toks.some(x => x.startsWith(t))) best = Math.max(best, w * 0.6); } if (best) hit++; total += best; }
  return hit === terms.length ? total * 1.5 : total;
}
function visibleItems() {
  if (state.mode === "propose") return state.items;
  let items = state.items.filter(i => tab === "all" || (tab === "rising" ? i.rising : i.kind === tab));
  const terms = words(query).filter(t => !["a","an","the","of","and","or","meme","gif"].includes(t));
  if (!terms.length) return items;
  return items.map(i => [i, score(i, terms)]).filter(([, s]) => s > 0).sort((a, b) => b[1] - a[1] || (a[0].popularity || 999) - (b[0].popularity || 999)).map(([i]) => i);
}

function media(item, controls) {
  if (item.video) { const v = el("video", { muted: "", autoplay: "", loop: "", playsinline: "", preload: "metadata", ...(controls ? { controls: "" } : {}) }); v.muted = true; v.src = item.media; return v; }
  return el("img", { src: item.media, alt: item.title, loading: "lazy" });
}
function sub(item) {
  if (state.mode === "propose") return item.recipe || item.title;
  return item.vibe || ({ template: "Template", clip: "Clip", made: "Made" })[item.kind];
}

function renderKlipy(grid) {
  grid.className = "grid";
  if (!state.klipy.length) { grid.append(el("p", { class: "empty" }, "KLIPY found nothing for that.")); return; }
  for (const result of state.klipy) {
    const tile = el("div", { class: "tile" + (selected.includes(result.slug) ? " sel" : ""), tabindex: "0", role: "button", onclick: () => toggle(result.slug), onkeydown: e => { if (e.key === "Enter") toggle(result.slug); } },
      el("div", { class: "thumb" }, !result.preview ? el("span", { class: "sub" }, "No preview")
        : result.previewIsVideo ? (() => { const v = el("video", { muted: "", autoplay: "", loop: "", playsinline: "" }); v.muted = true; v.src = result.preview; return v; })()
        : el("img", { src: result.preview, alt: result.title, loading: "lazy" }), el("span", { class: "badge" }, "✓")),
      el("div", { class: "name" }, result.title));
    grid.append(tile);
  }
}

function renderGrid() {
  const grid = document.getElementById("grid");
  if (state.mode === "klipy") { grid.replaceChildren(); renderKlipy(grid); return; }
  grid.className = state.mode === "propose" ? "grid big" : "grid";
  grid.replaceChildren();
  const items = visibleItems();
  if (!items.length) { grid.append(el("p", { class: "empty" }, query ? "Nothing matches. Try a feeling, like “waiting” or “smug”." : "Nothing here yet.")); return; }
  items.slice(0, 400).forEach((item, n) => {
    const index = selected.indexOf(item.id);
    const tile = el("div", { class: "tile" + (index >= 0 ? " sel" : "") + (state.mode === "propose" ? " num" : ""), tabindex: "0", role: "button", "aria-pressed": index >= 0 ? "true" : "false", "data-id": item.id,
      onclick: () => toggle(item.id), onkeydown: e => { if (e.key === " ") { e.preventDefault(); detail(item); } else if (e.key === "Enter") { e.preventDefault(); toggle(item.id); } } },
      el("div", { class: "thumb" }, media(item, false), el("span", { class: "badge" }, state.mode === "propose" ? String(n + 1) : (state.max > 1 ? String(index + 1) : "✓")),
        el("button", { class: "info", title: "Details", "aria-label": "Details for " + item.title, onclick: e => { e.stopPropagation(); detail(item); } }, "i")),
      el("div", { class: "name" }, state.mode === "propose" ? (item.captions.filter(Boolean).join(" / ") || item.title) : item.title), el("div", { class: "sub" }, sub(item)));
    grid.append(tile);
  });
}

function toggle(id) {
  const max = state.mode === "propose" || state.mode === "klipy" ? 1 : state.max;
  const i = selected.indexOf(id);
  if (i >= 0) selected.splice(i, 1);
  else { if (max === 1) selected = []; if (selected.length >= max) selected.shift(); selected.push(id); }
  if (state.mode === "browse") savePicks([...selected]);
  renderGrid(); renderFooter(); renderStatus();
}

// Saves run one after another, so the server always ends up with the latest selection.
function savePicks(picks) {
  saving = saving.then(() => api("/api/picks", { chosen: picks, note: "" })).then(ok => {
    saved = ok; document.getElementById("error").textContent = "";
  }).catch(e => {
    selected = [...saved];
    document.getElementById("error").textContent = "Picks not saved: " + e.message;
    renderGrid(); renderFooter(); renderStatus();
  });
}

function detail(item) {
  const dialog = document.getElementById("dialog");
  const picked = selected.includes(item.id);
  const lines = [];
  if (item.vibe) lines.push(el("p", {}, el("b", {}, "Feeling: "), item.vibe));
  if (item.howUsed) lines.push(el("p", {}, el("b", {}, "How it’s used: "), item.howUsed));
  if (item.captions.length) lines.push(el("p", {}, el("b", {}, "Captions: "), item.captions.filter(Boolean).join(" / ")));
  if (item.tags.length) lines.push(el("p", {}, el("b", {}, "Tags: "), item.tags.slice(0, 8).join(", ")));
  lines.push(el("p", {}, el("b", {}, "Source: "), item.source + (item.licence ? ". " + item.licence : "")));
  if (item.attribution) lines.push(el("p", {}, el("b", {}, "Credit: "), item.attribution));
  dialog.replaceChildren(el("div", { class: "detail" },
    el("div", { class: "thumb" }, media(item, true)),
    el("div", {}, el("h2", {}, item.title), ...lines, el("span", { class: "rights" }, item.rights),
      el("div", { class: "row" },
        el("button", { class: "pill primary", onclick: () => { toggle(item.id); dialog.close(); } }, picked ? "Unpick" : (state.mode === "propose" ? "Choose" : "Pick")),
        el("button", { class: "pill", onclick: () => dialog.close() }, "Close")))));
  dialog.showModal();
}

function renderStatus() {
  const s = document.getElementById("status");
  if (state.mode === "klipy") s.textContent = "Pick one to share its link.";
  else if (state.mode === "propose") s.textContent = (state.from || "The agent") + " has " + state.items.length + " option" + (state.items.length === 1 ? "" : "s") + ". Pick one, or say what to change.";
  else if (state.mode === "pick") s.textContent = "Pick up to " + state.max + ". " + selected.length + " picked.";
  else s.textContent = state.total + " memes. " + selected.length + " picked.";
}

function renderFooter() {
  const footer = document.getElementById("footer");
  const typed = Object.fromEntries([...footer.querySelectorAll("input")].map(i => [i.id, i.value]));
  footer.replaceChildren();
  const keep = input => { input.value = typed[input.id] || ""; return input; };
  const byID = Object.fromEntries(state.items.map(i => [i.id, i]));
  if (state.mode === "klipy") {
    const use = el("button", { class: "pill primary", onclick: () => finish(selected, "") }, "Use this link");
    if (!selected.length) use.disabled = true;
    footer.append(el("span", { class: "chips sub" }, "Powered by KLIPY. Links only: shared as KLIPY serves them."), use);
    return;
  }
  if (state.mode === "propose") {
    const note = keep(el("input", { id: "note", placeholder: "Or tell the agent what to change, like “2, shorter caption”", autocomplete: "off" }));
    const send = el("button", { class: "pill primary", onclick: () => finish(selected, note.value) }, "Send back");
    if (!selected.length) send.disabled = true;
    footer.append(note, send, el("button", { class: "pill", onclick: () => finish([], note.value) }, "None of these"));
    return;
  }
  const chips = el("div", { class: "chips" }, ...selected.map(id => el("span", { class: "chip" }, (byID[id] || { title: id }).title, el("button", { "aria-label": "Remove", onclick: () => toggle(id) }, "✕"))));
  if (!selected.length) chips.append(el("span", { class: "sub" }, state.mode === "pick" ? "Click memes to pick them." : "Click memes to pick them for an agent."));
  footer.append(chips);
  if (state.mode === "pick") {
    const use = el("button", { class: "pill primary", onclick: () => finish(selected, "") }, "Use these (" + selected.length + ")");
    if (!selected.length) use.disabled = true;
    footer.append(use);
  } else {
    const idea = keep(el("input", { id: "idea", placeholder: "Idea, like “me watching CI”", autocomplete: "off" }));
    const copy = el("button", { class: "pill primary", onclick: async () => {
      const prompt = "Use Meme Lab (the `meme` command). Run `meme picks` to see the memes I picked (" + selected.join(", ") + "), then make a meme that combines them" + (idea.value.trim() ? ": " + idea.value.trim() : "") + ". Show me the options with `meme propose`.";
      await navigator.clipboard.writeText(prompt); copy.textContent = "Copied"; setTimeout(() => copy.textContent = "Copy prompt", 1500);
    } }, "Copy prompt");
    if (!selected.length) copy.disabled = true;
    footer.append(idea, copy);
  }
}

async function finish(chosen, note) {
  try { await api("/api/choose", { chosen, note }); }
  catch (e) { document.getElementById("status").textContent = "That didn’t reach the agent: " + e.message; return; }
  document.body.replaceChildren(el("div", { class: "done" }, el("h2", {}, chosen.length ? "Sent back to the agent." : "Sent your note to the agent."), el("p", {}, "You can close this tab.")));
}

function setUpKlipySearch(initial) {
  const search = document.getElementById("search");
  search.placeholder = "Search KLIPY";
  search.setAttribute("aria-label", "Search KLIPY");
  search.value = initial || "";
  search.replaceWith(search.cloneNode(true));
  const box = document.getElementById("search");
  let latest = 0;
  box.addEventListener("keydown", async e => {
    if (e.key !== "Enter" || !box.value.trim()) return;
    const mine = ++latest;
    document.getElementById("status").textContent = "Searching KLIPY…";
    try {
      const results = await api("/api/klipy?q=" + encodeURIComponent(box.value.trim()));
      if (mine !== latest) return;
      state.klipy = results; selected = []; document.getElementById("error").textContent = "";
    } catch (err) {
      if (mine === latest) document.getElementById("error").textContent = "KLIPY search failed: " + err.message;
    }
    if (mine === latest) { renderGrid(); renderFooter(); renderStatus(); }
  });
}

function renderTabs() {
  const box = document.getElementById("tabs");
  box.replaceChildren(...tabs.filter(([key]) => key !== "rising" || state.items.some(i => i.rising)).map(([key, label]) => el("button", { class: "tab" + (tab === key ? " on" : ""), onclick: () => { tab = key; renderTabs(); renderGrid(); } }, label)));
}

document.getElementById("search").addEventListener("input", e => { query = e.target.value; renderGrid(); });
document.addEventListener("keydown", e => {
  if (e.key === "/" && document.activeElement.tagName !== "INPUT") { e.preventDefault(); document.getElementById("search").focus(); }
  if (state && state.mode === "propose" && document.activeElement.tagName !== "INPUT" && /^[1-9]$/.test(e.key)) { const item = state.items[Number(e.key) - 1]; if (item) toggle(item.id); }
});

api("/api/state").then(s => {
  state = s;
  selected = s.mode === "browse" ? s.picks.filter(id => s.items.some(i => i.id === id)) : [];
  saved = [...selected];
  if (s.mode === "propose") document.getElementById("controls").remove();
  else if (s.mode === "klipy") setUpKlipySearch(s.query);
  else renderTabs();
  renderStatus(); renderGrid(); renderFooter();
}).catch(e => { document.getElementById("status").textContent = "Meme Lab isn’t answering: " + e.message; });
</script>
</body>
</html>
"""#
}
