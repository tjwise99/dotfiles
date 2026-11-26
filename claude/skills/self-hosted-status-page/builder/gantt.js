/* ganttChart(host, schedule, {updated:"HH:MM", date:"YYYY-MM-DD"}): draws schedule.json as it is. */
(function () {
"use strict";
let LANES = [["work", "Work"], ["gates", "Reviews and gates"]];
const KIND = { running: ["▶", "Running"], waiting: ["○", "Waiting"], passed: ["✓", "Passed"], failed: ["✗", "Failed"], "failed as designed": ["✗", "Failed as designed"],
  hold: ["‖", "Hold"], idle: ["·", "Idle"], void: ["⊘", "Void"], stopped: ["■", "Stopped"], "not proven": ["?", "Not proven"], cut: ["✂", "Cut"], dropped: ["—", "Dropped"], ended: ["◌", "Ended, no outcome yet"], unknown: ["?", "Unknown state"] };
const CLS = { "failed as designed": "design", "not proven": "np" };
let RES = {}; const RIB = 28, GAP = 10;
const LW = 184, TWO = 48, ONE = 34, CLOSED = 24, PADR = 18, STALE = 10, DIFF = 5, NARROW = 600;
const mm = s => { const m = /^(\d\d):(\d\d)/.exec(s || ""); return m ? +m[1] * 60 + +m[2] : null; };
const hm = m => (m > 1440 ? hm(m - 1440) : "") || String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(Math.floor(m % 60)).padStart(2, "0");
const el = (t, c, ...k) => { const e = document.createElement(t); if (c) e.className = c; e.append(...k.filter(x => x != null && x !== "")); if (t === "button") e.type = "button"; return e; };
const css = (e, o) => { for (const k in o) e.style[k] = typeof o[k] === "number" ? o[k] + "px" : o[k]; return e; };

/* A lane field wins; without one, a people's job that is no review or gate is analysis. */
const laneOf = j => j.lane || j.group;
function shortName(j) {
  if (j.name) return j.name;
  let s = (j.label || j.id).replace(new RegExp("^" + j.id.replace(/[^\w]/g, "\\$&") + "\\s*:\\s*"), "").replace(/\s*\([^)]*\)?/g, "").replace(/`/g, "");
  const cut = s.slice(6).search(/[:;,]/);
  if (cut >= 0) s = s.slice(0, cut + 6);
  if (s.length > 38) s = s.slice(0, 37).replace(/\s+\S*$/, "") + "…";
  return s.charAt(0).toUpperCase() + s.slice(1);
}
function clock(date, tz) {
  const p = {}; new Intl.DateTimeFormat("en-GB", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date()).forEach(q => p[q.type] = q.value);
  const day = date ? (Date.parse(`${p.year}-${p.month}-${p.day}`) - Date.parse(date)) / 864e5 : 0;
  return day === 0 || day === 1 ? day * 1440 + (+p.hour % 24) * 60 + +p.minute : null;
}

window.ganttChart = function (host, G, opt) {
  opt = opt || {};
  if (G.lanes) LANES = G.lanes;
  if (G.resources) RES = G.resources;
  /* minutes from 00:00 of the window's first day: a job's `day` is the date of its start, and an end before its start is the next day */
  const WD = G.window_days || [], D0 = Date.parse(WD[0] || G.date || opt.date || "1970-01-01"), dayOff = d => d ? Math.round((Date.parse(d) - D0) / 864e5) * 1440 : 0;
  const T0 = mm((G.window || [])[0]) ?? 0, END = (mm((G.window || [])[1]) ?? 1440) + (WD[1] ? dayOff(WD[1]) : 0), TZ = G.timezone || opt.timezone || "UTC";
  const FINAL = (m => m == null ? 1320 : m < 360 ? m + 1440 : m)(mm(G.final_start || "22:00"));
  const st = { whole: false, open: new Set(), sel: null, scroll: null };
  const byId = {}, kids = {};
  let now, from, jobs, holds, T1 = END;
  const at = s => { const m = mm(s); if (m == null) return null; if (now == null) return m; let best = m; for (const k of [m + 1440, m + 2880]) if (Math.abs(k - now) < Math.abs(best - now)) best = k; return best; }; /* a clock time with no date is the day nearest to now */
  const hs = h => { const f = mm(h.from), b = f != null && f < 360 ? 1440 : 0, s = (f ?? 0) + b; let e = (mm(h.to) ?? 0) + b; if (e < s) e += 1440; return [s, e]; }; /* a hold that starts before 06:00 is on the second day */
  const tm = j => { const p = j.planned || [], a = j.actual || [], b = dayOff(j.day), A = x => mm(x) == null ? null : mm(x) + b;
    const p0 = A(p[0]), a0 = A(a[0]); let p1 = A(j.planned_end) ?? A(p[1]), a1 = A(a[1]);
    if (p1 != null && (p0 ?? a0) != null && p1 < (p0 ?? a0)) p1 += 1440; if (a1 != null && a0 != null && a1 < a0) a1 += 1440;
    return { p0, p1, a0, a1 }; };

  function load() {
    now = opt.now != null ? mm(opt.now) : clock(G.date || opt.date, TZ);
    /* work still open after the window keeps the chart live for up to three hours more */
    T1 = now > END && (G.jobs || []).some(j => j.state === "running" || j.state === "waiting") ? Math.min(END + 180, Math.ceil((now + 15) / 60) * 60) : END;
    if (now > T1) now = null;
    from = now == null ? T0 : Math.max(T0, Math.min(now - 120, T1 - 180));
    jobs = (G.jobs || []).map(j => {
      const p = j.planned || [], a = j.actual || [], r = (j.outcome || {}).result;
      const k = j.state === "running" || j.state === "waiting" ? j.state : KIND[r] ? r : r ? "unknown" : j.state === "cut" ? "cut" : j.state === "failed" ? "failed" : j.state === "done" ? "ended" : "unknown";
      const o = { j, id: j.id, k, lane: laneOf(j), name: shortName(j), p0: tm(j).p0, p1: tm(j).p1, a0: tm(j).a0, a1: tm(j).a1 };
      o.s = o.a0 ?? o.p0;
      o.e = o.s == null ? null : o.a1 ?? (k === "running" ? Math.max(now ?? 0, o.p1 ?? 0, o.s) : o.a0 != null ? o.a0 : o.p1 ?? o.s);
      o.late = now == null ? 0 : k === "running" && o.p1 != null ? now - o.p1 : k === "waiting" && o.p0 != null ? now - o.p0 : 0;
      if (j.late_since && o.late <= 0 && now != null && at(j.late_since) != null) o.late = Math.max(1, now - at(j.late_since)); /* the scheduler's LATE: an open job past its planned end */
      o.at = at((j.progress || {}).at); o.stale = k === "running" && now != null && o.at != null && now - o.at > STALE; o.ahead = now != null && o.at != null && o.at > now + 2;
      o.off = o.a0 != null && o.p0 != null && (Math.abs(o.a0 - o.p0) > DIFF || (o.a1 != null && o.p1 != null && Math.abs(o.a1 - o.p1) > DIFF));
      o.closed = k === "cut" || k === "dropped" || (k !== "running" && k !== "waiting" && (st.whole || o.s == null || o.e < from));
      return byId[o.id] = o;
    });
    holds = (G.idle_reasons || []).map((h, i) => byId["hold-" + i] = { id: "hold-" + i, k: "hold", lane: RES[h.resource] || h.resource, s: hs(h)[0], e: hs(h)[1], why: h.why || "no reason recorded",
      name: (h.why || "").replace(/^[A-Z]\w*\d+:\s*/, "").split(/\s*[(;,]/)[0].replace(/^(.{30}\S*).+/, "$1…") }).filter(h => h.s != null && h.e > h.s);
    holds.forEach(h => h.closed = !st.whole && h.e < from);
    jobs.forEach(o => kids[o.id] = jobs.filter(x => (x.j.waits_on || []).includes(o.id)).map(x => x.id));
  }
  const high = o => over(o) || (st.whole && o.k === "waiting" && o.late <= 0) ? ONE : TWO;
  function idle(lane) { /* gaps of 10 min or more with no job and no hold, on a lane that is a machine */
    if (!Object.values(RES).includes(lane)) return [];
    const use = jobs.filter(o => o.lane === lane && o.s != null && o.k !== "cut" && o.k !== "dropped").map(o => [o.s, Math.max(o.e, o.s + 1)]), out = [];
    let t = T0; for (const [a, z] of use.concat(holds.filter(h => h.lane === lane).map(h => [h.s, h.e])).sort((x, y) => x[0] - y[0])) { if (a - t >= GAP) out.push([t, a]); t = Math.max(t, z); }
    if (T1 - t >= GAP) out.push([t, T1]);
    return { gaps: out.map(([a, z], i) => byId[`idle-${lane}-${i}`] = { id: `idle-${lane}-${i}`, k: "idle", lane, s: a, e: z, why: "no reason recorded", name: "idle", closed: z < from }) };
  }
  const cls = o => CLS[o.k] || o.k;
  const over = o => o && o.k !== "running" && o.k !== "waiting";
  const blockers = o => (o.j.waits_on || []).filter(w => !over(byId[w]));
  function chain(id) {
    const s = new Set([id]), go = (i, f) => (f(i) || []).forEach(n => { if (byId[n] && !s.has(n)) { s.add(n); go(n, f); } });
    go(id, i => byId[i].j.waits_on); const up = [...s]; go(id, i => kids[i]);
    return { set: s, before: up.slice(1), after: [...s].slice(up.length) };
  }
  function pill(o, full) {
    const [m, w] = KIND[o.k], word = full || !/^(passed|running|waiting)$/.test(o.k);
    const t = o.k === "unknown" ? w + ": " + ((o.j.outcome || {}).result || o.j.state) : w;
    return el("span", "g2-pill k-" + cls(o), word ? m + " " + t : m);
  }
  function note(o, long) { /* second line: state in words, then the id */
    const b = el("span", "g2-sub"), add = (t, c) => { if (b.childNodes.length) b.append(" · "); b.append(el("span", c, t)); }, g = o.j.progress;
    if (o.k === "running") {
      if (g && g.total) add(`${g.done} of ${g.total}` + (o.stale || o.at == null ? "" : ", updated " + hm(o.at))); else add("no count reported");
      if (o.ahead) add("that time is ahead of the clock", "warn"); if (o.stale) add("no update since " + hm(o.at), "warn");
      if (o.late > 0) add("late " + o.late + " min", "late");
    } else if (o.k === "waiting") {
      const w = blockers(o); if (w.length) add("waits on " + w.join(", "));
      if (o.late > 0) add("late, due " + hm(o.p0), "late"); else if (o.p0 != null && (long || !w.length)) add("due " + hm(o.p0)); else if (o.p0 == null) add("no time set");
    }
    add(o.id, "id"); return b;
  }
  const span = (a, b) => a == null ? "none recorded" : b == null ? hm(a) + ", not ended" : `${hm(a)} to ${hm(b)} (${b - a} min)`;
  function detail(o, full) {
    if (!o.j) { const d = el("div", "g2-detail"); d.append(el("div", "g2-dh", pill(o, true), " ", el("b", "", (lanes().find(l => l[0] === o.lane) || [, o.lane])[1])));
      for (const [k, v] of [["Time", span(o.s, o.e)], ["Why", o.why]]) d.append(el("div", "g2-kv", el("span", "", k), el("span", "", v))); return d; }
    const d = el("div", "g2-detail"), j = o.j, out = j.outcome || {}, g = j.progress, row = (k, v) => v && d.append(el("div", "g2-kv", el("span", "", k), el("span", "", v)));
    d.append(el("div", "g2-dh", pill(o, true), " ", el("b", "", o.name), " ", el("span", "g2-sub", o.id)));
    if (full) row("Job", j.label);
    row("Planned", o.p0 == null ? (o.p1 == null ? "none recorded" : "to end " + hm(o.p1)) : span(o.p0, o.p1)); row("Actual", span(o.a0, o.a1));
    if (o.k === "running") { row("Progress", g ? `${g.done} of ${g.total}: ${g.label || ""}` : "no progress reported"); if (full && g) row("Latest", (g.latest || "") + (g.at ? ` (${g.at})` : "")); }
    if (o.late > 0) row("Late", o.k === "running" ? `${o.late} min past its planned end` : `${o.late} min past its planned start`);
    row("Decides", j.decides);
    row("Waits on", (j.waits_on || []).map(w => byId[w] ? `${byId[w].name}, ${w} (${KIND[byId[w].k][1].toLowerCase()})` : w).join("; ") || "nothing");
    if (over(o)) row("Outcome", KIND[o.k][1] + (out.why ? ": " + out.why : o.k === "ended" ? "" : ", no reason recorded"));
    if (over(o)) row("Record", out.record || j.evidence || "none named");
    if (full) {
      row("Note", j.note); const c = chain(o.id), list = ids => ids.length ? ids.join(", ") : "nothing";
      row("Chain", `${list(c.before)} before it; ${list(c.after)} after it`);
    }
    return d;
  }
  const select = id => { st.sel = st.sel === id ? null : id; draw(); };
  const order = (a, b) => (a.s ?? 9999) - (b.s ?? 9999) || (a.e ?? 0) - (b.e ?? 0);
  function item(o) {
    if (o.k === "idle") return [el("div", "g2-idlerow", el("span", "g2-time", hm(o.s) + "–" + hm(o.e)), el("span", "", "idle, no reason"))];
    const b = el("button", "g2-item" + (st.sel === o.id ? " on" : ""), el("span", "g2-time", o.s == null ? "no time" : hm(o.s) + (o.e > o.s || o.k === "running" ? "–" + (o.k === "running" ? (o.p1 != null ? hm(o.p1) : "") : hm(o.e)) : "")),
      el("span", "g2-body", pill(o, true), " ", el("span", "g2-nm", o.j ? o.name : o.why), o.j ? note(o, true) : ""));
    if (o.k === "running" && (o.j.progress || {}).total) b.lastChild.append(el("span", "g2-meter", css(el("i"), { width: 100 * o.j.progress.done / o.j.progress.total + "%" })));
    if (o.k === "hold") b.classList.add("g2-holdrow"); b.dataset.id = o.id; b.setAttribute("aria-expanded", st.sel === o.id); b.onclick = () => select(o.id);
    return st.sel === o.id && host.clientWidth < NARROW ? [b, detail(o, true)] : [b];
  }
  function closedToggle(lane, list) {
    const b = el("button", "g2-tog", (st.open.has(lane) ? "▾ " : "▸ ") + list.length + " closed");
    for (const k of ["failed", "failed as designed", "void", "stopped", "not proven", "unknown"]) { const n = list.filter(o => o.k === k).length; if (n) b.append(" ", el("span", "g2-pill k-" + (CLS[k] || k), KIND[k][0] + " " + n)); }
    b.title = st.whole ? "Finished, cut or dropped" : "Finished more than two hours ago, cut or dropped"; b.setAttribute("aria-expanded", st.open.has(lane));
    b.onclick = () => { st.open.has(lane) ? st.open.delete(lane) : st.open.add(lane); draw(); };
    return b;
  }
  function head() {
    const n = k => jobs.filter(o => o.k === k).length, mode = (w, t) => { const b = el("button", "", t); b.setAttribute("aria-pressed", st.whole === w); b.onclick = () => { st.whole = w; st.scroll = null; draw(); }; return b; };
    const age = now != null && at(opt.updated) != null ? now - at(opt.updated) : null;
    const status = el("span", "g2-status", el("b", "", now == null ? "This schedule's day is over" : "Now " + hm(now) + " " + (G.tz_label || TZ)), opt.updated ? " · schedule written " + opt.updated : "", age != null && age > 60 ? el("span", "warn", ` · ${age} min old`) : "");
    const key = el("div", "g2-key");
    for (const k in KIND) if (n(k)) key.append(el("span", "", el("i", "g2-bar k-" + (CLS[k] || k)), KIND[k][0] + " " + KIND[k][1] + " ", el("b", "", String(n(k)))));
    const late = jobs.filter(o => o.late > 0).length, stale = jobs.filter(o => o.stale).length;
    if (late) key.append(el("span", "late", "Late ", el("b", "", String(late))));
    if (stale) key.append(el("span", "warn", "No recent update ", el("b", "", String(stale))));
    key.append(el("span", "", el("i", "g2-plan"), "Planned, where more than 5 min off"));
    key.append(el("span", "", el("i", "g2-hold"), "‖ Hold, with a reason ", el("b", "", String(holds.length))), el("span", "", el("i", "g2-idle"), "Idle, no reason"));
    const top = el("div", "g2-head", status);
    if (host.clientWidth >= NARROW) top.append(el("span", "g2-modes", mode(false, "2 hours ago to " + hm(T1)), mode(true, "Whole day")));
    return [top, key];
  }
  function drawList() {
    const root = el("div", "g2-list");
    for (const [lane, title] of lanes()) {
      const g = idle(lane), js = jobs.concat(holds, g.gaps || []).filter(o => o.lane === lane).sort(order), open = js.filter(o => !o.closed), shut = js.filter(o => o.closed && o.k !== "idle");
      root.append(el("section", "", el("h4", "", title), ...open.flatMap(item), open.length ? "" : el("div", "g2-none", "Nothing in this window"), shut.length ? closedToggle(lane, shut) : "", ...(st.open.has(lane) ? shut.flatMap(item) : [])));
    }
    host.append(root);
  }
  const lanes = () => LANES.concat([...new Set(jobs.map(o => o.lane))].filter(l => !LANES.some(x => x[0] === l)).map(l => [l, l]));

  function drawChart() {
    const box = el("div", "g2-box"), inner = el("div", "g2-in"); box.tabIndex = 0; box.setAttribute("aria-label", "Schedule chart, scrolls sideways"); host.append(box); box.append(inner);
    const px = (box.clientWidth - LW - PADR) / (st.whole || now == null ? T1 - T0 : T1 - from), W = (T1 - T0) * px + PADR, X = m => (Math.max(T0, Math.min(T1, m)) - T0) * px;
    css(inner, { width: LW + W });
    const axis = css(el("div", "g2-plot"), { width: W }); inner.append(el("div", "g2-axis", el("div", "g2-name"), axis));
    const taken = [], tick = (m, t, c, end) => { const e = css(el("span", c, t), { left: X(m) }); axis.append(e); const w = e.offsetWidth, l = Math.min(X(m) - (end ? w - 17 : w / 2), W - w - 2); if (taken.some(q => l < q[1] + 8 && l + w > q[0] - 8)) return e.remove(); taken.push([l, l + w]); css(e, { left: Math.max(0, l) }); };
    if (T0 < 1440 && END > 1440) tick(1440, "midnight", "hr mk"); tick(END, hm(END), "hr mk"); if (T1 > END) tick(T1, hm(T1), "hr"); if (FINAL > T0 && FINAL < T1) tick(FINAL, "final work " + hm(FINAL), "hr mk", true);
    for (let h = Math.ceil(T0 / 60); h * 60 < T1; h++) if (!((h % Math.ceil(52 / (60 * px))))) tick(h * 60, hm(h * 60), "hr");
    const s0 = mm((G.stall || [])[0]), s1 = mm((G.stall || [])[1]);
    if (s0 != null && s1 != null) axis.append(css(el("span", "stall", `no work ${hm(s0)} to ${hm(s1)}`), { left: X(s0), width: X(s1) - X(s0) }));
    const line = (m, c) => inner.append(css(el("i", "g2-line " + c), { left: LW + X(m) }));
    if (FINAL > T0 && FINAL < T1) line(FINAL, ""); if (T0 < 1440 && END > 1440) line(1440, ""); line(END, "");
    if (now != null && now >= T0 && now <= T1) { line(now, "now"); const p = el("span", "nowp", "now " + hm(now)); axis.append(p); css(p, { left: Math.min(X(now) - p.offsetWidth / 2, W - p.offsetWidth) }); }

    for (const [lane, title] of lanes()) {
      const js = jobs.filter(o => o.lane === lane).sort(order), ig = idle(lane); if (!js.length && !holds.some(h => h.lane === lane)) continue;
      const open = js.filter(o => !o.closed && o.s != null), odd = js.filter(o => !o.closed && o.s == null), shut = js.filter(o => o.closed), rows = [], set = [];
      const plot = css(el("div", "g2-plot"), { width: W }), name = el("div", "g2-name", el("b", "", title)), next = open.find(o => o.k === "waiting"), run = open.filter(o => o.k === "running").length;
      name.append(el("span", "g2-sub", (run ? run + " running" : "nothing running") + (next ? ", next " + hm(next.s) : "")));
      inner.append(el("div", "g2-lane", name, plot));
      for (const o of open) {
        const x0 = X(o.s), x1 = Math.max(x0 + 5, X(o.e)), lab = el("span", "g2-lab", el("span", "g2-l1", pill(o), " ", el("span", "g2-nm", o.name), over(o) ? el("span", "g2-sub", " ", el("span", "id", o.id)) : ""), high(o) === ONE ? "" : note(o)), b = el("button", "g2-job k-" + cls(o), lab);
        plot.append(b); const lw = Math.ceil(lab.offsetWidth) + 2, lx = Math.min(st.whole ? x0 : Math.max(x0, X(from) + 8), W - lw - 4); let L = Math.min(x0, lx), R = Math.max(x1, lx + lw);
        if (o.off) { L = Math.min(L, X(o.p0)); R = Math.max(R, X(o.p1 ?? o.p0)); }
        let r = rows.findIndex(q => q.every(([a, z]) => R + 8 <= a || L >= z + 8)); if (r < 0) r = rows.push([]) - 1; rows[r].push([L, R]); rows[r].h = Math.max(rows[r].h || 0, high(o)); set.push([b, r, o]);
        css(b, { left: L, width: R - L });
        css(lab, { marginLeft: lx - L });
        if (o.off) b.append(css(el("i", "g2-plan"), { left: X(o.p0) - L, width: Math.max(5, X(o.p1 ?? o.p0) - X(o.p0)) }));
        const bar = css(el("i", "g2-bar k-" + cls(o)), { left: x0 - L, width: x1 - x0 }), g = o.j.progress;
        if (o.k === "running" && g && g.total) bar.append(css(el("i", "fill"), { width: 100 * g.done / g.total + "%" }));
        if (o.k === "running" && o.late > 0) bar.append(css(el("i", "lateseg"), { left: X(o.p1) - x0, right: 0 }));
        b.append(bar); wire(b, o, box);
      }
      let h = ig.gaps ? RIB + 4 : 6; if (ig.gaps) { const took = [];
        for (const o of holds.filter(q => q.lane === lane)) { const b = css(el("button", "g2-hold"), { left: X(o.s), width: Math.max(6, X(o.e) - X(o.s)) }), t = el("span", "", el("b", "", "‖ Hold"), " " + o.name); plot.append(b); b.append(t);
          for (const f of [() => t.lastChild.remove(), () => t.firstChild.textContent = "Hold"]) if (t.offsetWidth > b.clientWidth) f();
          if (t.offsetWidth > b.clientWidth) { t.remove(); if (holds.some(q => q.lane === lane && q.s > o.s && X(q.s) < X(o.e) + 44)) { wire(b, o, box); continue; } const l = css(el("span", "g2-holdlab", "Hold"), { left: X(o.e) + 4 }); plot.append(l); took.push([X(o.e), X(o.e) + l.offsetWidth + 8]); } wire(b, o, box); }
        for (const o of ig.gaps) { const g = css(el("i", "g2-idle"), { left: X(o.s), width: X(o.e) - X(o.s) }), c = (X(o.s) + X(o.e)) / 2; g.title = `Idle ${hm(o.s)} to ${hm(o.e)}, no reason recorded`; plot.append(g);
          if (X(o.e) - X(o.s) > 56 && !took.some(([a, z]) => c + 20 > a && c - 20 < z)) g.append(el("span", "", "idle")); }
      }
      rows.forEach(q => { q.y = h; h += q.h; }); set.forEach(([b, r, o]) => css(b, { top: rows[r].y, height: high(o) - 4 }));
      h = Math.max(h, 44);
      if (!rows.length) { plot.append(css(el("span", "g2-none", st.whole ? "Nothing running or waiting" : "Nothing in this window"), { marginTop: ig.gaps ? RIB : 0 })); }
      if (odd.length) { plot.append(css(el("div", "g2-odd", "No time set: ", ...odd.flatMap(item)), { top: h, width: box.clientWidth - LW - 12 })); h += plot.lastChild.offsetHeight; }
      if (shut.length) {
        name.append(css(closedToggle(lane, shut), { top: h }));
        for (const o of shut) if (o.s != null) { const x0 = X(o.s), b = css(el("button", "g2-seg k-" + cls(o), el("i", "g2-bar k-" + cls(o))), { left: x0, width: Math.max(6, X(o.e) - x0), top: h }); plot.append(b); wire(b, o, box); }
        h += CLOSED;
        if (st.open.has(lane)) { const l = css(el("div", "g2-shut", ...shut.flatMap(item)), { marginTop: h, width: box.clientWidth - LW - 2 }); plot.append(l); h += l.offsetHeight; }
      }
      css(plot, { height: h });
    }
    const home = st.whole || now == null ? 0 : X(from); box.scrollLeft = st.scroll ?? home;
    box.onscroll = () => { tip.hidden = true; st.scroll = Math.abs(box.scrollLeft - home) < 3 ? null : box.scrollLeft; };
    if (st.sel && byId[st.sel]) { const p = el("div", "g2-panel", detail(byId[st.sel], true)), x = el("button", "g2-x", "Close"); x.onclick = () => select(st.sel); p.append(x); host.append(p); }
  }
  const tip = el("div", "g2-tip"); tip.hidden = true;
  function wire(b, o, box) {
    b.dataset.id = o.id; b.setAttribute("aria-label", `${o.j ? o.name : o.why}, ${KIND[o.k][1]}, ${o.s == null ? "no time" : hm(o.s) + " to " + hm(o.e)}`); b.setAttribute("aria-pressed", st.sel === o.id);
    const show = () => { tip.replaceChildren(detail(o, false)); tip.hidden = false; const h = host.getBoundingClientRect(), q = b.getBoundingClientRect(), bx = box.getBoundingClientRect(), l = Math.max(q.left, bx.left + LW) - h.left; css(tip, { left: Math.max(0, Math.min(l, h.width - tip.offsetWidth - 4)), top: q.bottom + tip.offsetHeight + 8 > innerHeight && q.top > tip.offsetHeight + 8 ? q.top - h.top - tip.offsetHeight - 4 : q.bottom - h.top + 4 }); };
    b.onmouseenter = b.onfocus = show; b.onmouseleave = b.onblur = () => tip.hidden = true; b.onclick = () => { tip.hidden = true; select(o.id); };
  }
  function draw() {
    const f = document.activeElement && host.contains(document.activeElement) ? document.activeElement.dataset.id : null;
    load(); host.classList.add("g2"); host.replaceChildren(...head()); tip.hidden = true;
    host.clientWidth < NARROW ? drawList() : drawChart(); host.append(tip);
    if (st.sel && byId[st.sel] && byId[st.sel].j) { const c = chain(st.sel).set; host.classList.add("sel"); host.querySelectorAll("[data-id]").forEach(e => e.classList.toggle("in", c.has(e.dataset.id))); } else host.classList.remove("sel");
    if (f) { const e = host.querySelector(`[data-id="${CSS.escape(f)}"]`); if (e) { e.focus({ preventScroll: true }); tip.hidden = true; } }
  }
  let wide = 0; new ResizeObserver(() => { if (host.clientWidth && host.clientWidth !== wide) { wide = host.clientWidth; st.scroll = null; requestAnimationFrame(draw); } }).observe(host);
  host.addEventListener("keydown", e => { if (e.key === "Escape" && st.sel) select(st.sel); });
  if (document.fonts) document.fonts.ready.then(() => host.clientWidth && draw());
  setInterval(() => { if (host.clientWidth && tip.hidden) draw(); }, 60000);
};
})();
