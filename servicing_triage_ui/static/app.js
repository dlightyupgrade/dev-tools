(() => {
  const TOKEN = document.querySelector('meta[name="triage-token"]').content;
  const $ = (id) => document.getElementById(id);
  const DISPOSITIONS = { bug: "Bug", ops: "Needs a person", review: "No playbook" };
  const KNOWN_LABEL = { known: "Known", ticketed: "Ticketed", ignore: "Ignored" };
  const GROUPS = ["Payments", "Task queues", "Billing"];

  let state = null;
  let lastSignature = "";
  let pollTimer = null;
  const openRows = new Set();
  const view = { disposition: "all", group: "all", query: "", hideKnown: true };

  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const money = (value) => value.toLocaleString("en-US", { style: "currency", currency: "USD" });
  const groupOf = (finding) => (finding.area.endsWith("-tqf") ? "Task queues" : finding.area === "billing" ? "Billing" : "Payments");
  const ago = (iso) => {
    const seconds = Math.max(0, (Date.now() - Date.parse(iso)) / 1000);
    if (seconds < 90) return "just now";
    if (seconds < 5400) return Math.round(seconds / 60) + " min ago";
    if (seconds < 129600) return Math.round(seconds / 3600) + " h ago";
    return Math.round(seconds / 86400) + " d ago";
  };

  async function api(path, body) {
    const options = body === undefined ? {} : {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Triage-Token": TOKEN },
      body: JSON.stringify(body)
    };
    const response = await fetch(path, options);
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || response.statusText);
    return data;
  }

  let toastTimer = null;
  function toast(message) {
    const node = $("toast");
    node.textContent = message;
    node.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { node.hidden = true; }, 5000);
  }

  async function copyText(text, label) {
    try {
      await navigator.clipboard.writeText(text);
      toast(label + " copied");
    } catch (error) {
      const area = el("textarea");
      area.value = text;
      document.body.appendChild(area);
      area.select();
      const ok = document.execCommand("copy");
      area.remove();
      toast(ok ? label + " copied" : "Copy blocked by the browser");
    }
  }

  const runningJobs = () => (state ? state.jobs.filter((job) => job.status === "running") : []);

  function knownFor(finding) {
    return state.known[finding.id] || null;
  }

  function visibleFindings() {
    const query = view.query.toLowerCase();
    return state.report.findings.filter((finding) => {
      if (view.disposition !== "all" && finding.disposition !== view.disposition) return false;
      if (view.group !== "all" && groupOf(finding) !== view.group) return false;
      if (view.hideKnown && knownFor(finding)) return false;
      if (!query) return true;
      return [finding.title, finding.key, finding.code, finding.summary, finding.error_text].join(" ").toLowerCase().includes(query);
    });
  }

  function renderMeta() {
    const report = state.report;
    $("meta").textContent = report
      ? "Last " + report.window_days + (report.window_days === 1 ? " day" : " days") + ", fetched " + ago(report.fetched_at) + " (" + report.source + ")"
      : "No report yet";
    const refresh = $("refresh");
    const refreshing = runningJobs().some((job) => job.kind === "refresh");
    refresh.disabled = refreshing || !state.capabilities.headless;
    refresh.textContent = refreshing ? "Refreshing..." : "Refresh";
    refresh.title = state.capabilities.headless ? "Runs failure_triage headless. About 4 minutes and about $0.35." : "claude CLI not found";
  }

  function renderBanner() {
    const banner = $("banner");
    const running = runningJobs();
    const failed = state.jobs.find((job) => job.status === "error" && Date.now() / 1000 - (job.finished || 0) < 600);
    banner.replaceChildren();
    banner.className = "banner";
    if (running.length) {
      running.forEach((job) => {
        const seconds = Math.round(Date.now() / 1000 - job.started);
        banner.appendChild(el("span", "", job.label + " running, " + seconds + " s. Headless runs take a few minutes."));
      });
      banner.hidden = false;
    } else if (failed) {
      banner.classList.add("error");
      banner.appendChild(el("span", "", failed.label + " failed: " + failed.message));
      banner.hidden = false;
    } else {
      banner.hidden = true;
    }
  }

  function renderSummary() {
    const node = $("summary");
    node.replaceChildren();
    if (!state.report) return;
    const findings = state.report.findings;
    const count = (name) => findings.filter((finding) => finding.disposition === name).length;
    const open = findings.filter((finding) => !knownFor(finding)).length;
    const dollars = findings.reduce((sum, finding) => sum + (finding.dollars || 0), 0);
    const noMonitor = state.sumo.available ? findings.filter((finding) => finding.sumo && finding.sumo.total === 0).length : null;
    const cells = [
      [String(state.report.signatures), "signatures"],
      [String(state.report.failures), "failures"],
      [money(dollars), "payment dollars"],
      [String(count("bug")), count("bug") === 1 ? "bug" : "bugs"],
      [String(count("ops")), count("ops") === 1 ? "needs a person" : "need a person"],
      [String(open), "not marked known"]
    ];
    if (noMonitor !== null) cells.push([String(noMonitor), noMonitor === 1 ? "has no monitor mention" : "have no monitor mention"]);
    cells.forEach(([value, label]) => {
      const cell = el("div");
      cell.append(el("span", "num", value), el("span", "lbl", label));
      node.appendChild(cell);
    });
  }

  function renderUnchecked() {
    const panel = $("unchecked");
    const list = $("unchecked-list");
    list.replaceChildren();
    const items = state.report ? state.report.unchecked : [];
    panel.hidden = items.length === 0;
    items.forEach((item) => list.appendChild(el("li", "", item.name + ": " + item.reason)));
  }

  function chip(label, pressed, onClick) {
    const button = el("button", "chip", label);
    button.type = "button";
    button.setAttribute("aria-pressed", String(pressed));
    button.addEventListener("click", onClick);
    return button;
  }

  function renderFilters() {
    const dispositionNode = $("disposition-chips");
    const areaNode = $("area-chips");
    dispositionNode.replaceChildren();
    areaNode.replaceChildren();
    if (!state.report) return;
    const findings = state.report.findings;
    const entries = [["all", "All (" + findings.length + ")"]].concat(
      Object.keys(DISPOSITIONS).map((key) => [key, DISPOSITIONS[key] + " (" + findings.filter((f) => f.disposition === key).length + ")"]));
    entries.forEach(([key, label]) => dispositionNode.appendChild(chip(label, view.disposition === key, () => { view.disposition = key; renderView(); })));
    const groups = [["all", "All areas"]].concat(GROUPS.map((name) => [name, name + " (" + findings.filter((f) => groupOf(f) === name).length + ")"]));
    groups.forEach(([key, label]) => areaNode.appendChild(chip(label, view.group === key, () => { view.group = key; renderView(); })));
  }

  function table(columns, rows) {
    const wrap = el("div", "scroll");
    const grid = el("table");
    const head = el("tr");
    columns.forEach((name) => head.appendChild(el("th", "", name)));
    const thead = el("thead");
    thead.appendChild(head);
    const body = el("tbody");
    rows.forEach((cells) => {
      const row = el("tr");
      cells.forEach((cell) => row.appendChild(el("td", "mono", cell)));
      body.appendChild(row);
    });
    grid.append(thead, body);
    wrap.appendChild(grid);
    return wrap;
  }

  function block(title) {
    const node = el("div", "block");
    node.appendChild(el("h2", "", title));
    return node;
  }

  function fact(list, term, value, mono) {
    if (!value) return;
    const group = el("div");
    group.append(el("dt", "", term), el("dd", mono ? "mono" : "", value));
    list.appendChild(group);
  }

  function monitorsBlock(finding) {
    const node = block("Sumo monitors that mention this");
    if (!state.sumo.available) {
      node.appendChild(el("p", "note", "No monitor index. Run: python3 -m servicing_triage_ui sync-monitors"));
      return node;
    }
    const sumo = finding.sumo;
    if (!sumo || sumo.total === 0) {
      node.appendChild(el("p", "", "No monitor definition mentions this code, text or task."));
    } else {
      sumo.monitors.forEach((monitor) => {
        const card = el("div", "monitor");
        card.appendChild(el("b", "", monitor.name));
        const meta = el("div", "meta");
        meta.appendChild(el("span", "", "matched on " + monitor.matched_on.join(", ")));
        if (monitor.priority) meta.appendChild(el("span", "", monitor.priority));
        if (monitor.window) meta.appendChild(el("span", "", monitor.window + " window"));
        monitor.channels.forEach((channel) => meta.appendChild(el("span", "mono", "#" + channel)));
        if (monitor.incidentio) meta.appendChild(el("span", "", "incident.io"));
        card.appendChild(meta);
        node.appendChild(card);
      });
      if (sumo.total > sumo.monitors.length) node.appendChild(el("p", "note", (sumo.total - sumo.monitors.length) + " more not shown."));
    }
    node.appendChild(el("p", "note", "A mention is not coverage. This reads monitor definitions at " + (state.sumo.sha || "unknown") + ", not fired alerts."));
    return node;
  }

  function investigationBlock(finding) {
    const node = block("Investigation");
    const running = runningJobs().find((job) => job.kind === "investigate" && job.finding_id === finding.id);
    const saved = state.investigations[finding.id];
    if (running) node.appendChild(el("p", "", "Running headless, read-only tools only. Takes a few minutes."));
    if (saved) {
      node.appendChild(el("pre", "draft", saved.result || "(empty answer)"));
      const parts = [ago(saved.at)];
      if (saved.cost_usd != null) parts.push("$" + Number(saved.cost_usd).toFixed(2));
      if (saved.duration_ms) parts.push(Math.round(saved.duration_ms / 1000) + " s");
      node.appendChild(el("p", "note", "Model output, not a verified finding. " + parts.join(" · ")));
    } else if (!running) {
      node.appendChild(el("p", "note", "Runs claude headless with only the servicing-agent read tools allowed. Up to $" + state.capabilities.budget_usd.toFixed(2) + " per run."));
    }
    return node;
  }

  function knownBlock(finding) {
    const node = block("Known issue");
    const current = knownFor(finding);
    const form = el("div", "known-form");
    const select = el("select");
    select.id = "known-state-" + finding.id;
    select.setAttribute("aria-label", "Known issue state");
    [["open", "Open"], ["known", "Known cause"], ["ticketed", "Ticketed"], ["ignore", "Ignore"]].forEach(([value, label]) => {
      const option = el("option", "", label);
      option.value = value;
      select.appendChild(option);
    });
    select.value = current ? current.state : "open";
    const note = el("input");
    note.type = "text";
    note.id = "known-note-" + finding.id;
    note.placeholder = "Why (max 300 characters)";
    note.maxLength = 300;
    note.value = current ? current.note : "";
    note.setAttribute("aria-label", "Note");
    const ticket = el("input");
    ticket.type = "text";
    ticket.id = "known-ticket-" + finding.id;
    ticket.placeholder = "Jira key";
    ticket.value = current ? current.ticket : "";
    ticket.setAttribute("aria-label", "Jira key");
    const save = el("button", "btn", "Save");
    save.type = "button";
    save.addEventListener("click", async () => {
      try {
        await api("/api/known", { finding_id: finding.id, state: select.value, note: note.value, ticket: ticket.value });
        toast("Saved");
        await load();
      } catch (error) {
        toast(error.message);
      }
    });
    form.append(select, note, ticket, save);
    node.appendChild(form);
    node.appendChild(el("p", "note", "Stored on this machine only (" + (current ? "updated " + ago(current.updated_at) + " by " + current.by : "not marked") + ")."));
    return node;
  }

  function actionsBlock(finding) {
    const node = el("div", "actions");
    const open = el("button", "btn primary", "Open in Claude Code");
    open.type = "button";
    open.disabled = !state.capabilities.launch || !state.capabilities.headless;
    open.addEventListener("click", async () => {
      try {
        const result = await api("/api/launch", { finding_id: finding.id });
        toast(result.dry_run ? "Dry run: launch recorded, no terminal opened" : "Opened a new Claude Code session");
      } catch (error) {
        toast(error.message);
      }
    });
    const investigating = runningJobs().some((job) => job.kind === "investigate" && job.finding_id === finding.id);
    const run = el("button", "btn", investigating ? "Investigating..." : state.investigations[finding.id] ? "Run again" : "Run investigation");
    run.type = "button";
    run.disabled = investigating || !state.capabilities.headless;
    run.addEventListener("click", async () => {
      try {
        await api("/api/investigate", { finding_id: finding.id });
        toast("Investigation started");
        await load();
      } catch (error) {
        toast(error.message);
      }
    });
    node.append(open, run);
    const saved = state.investigations[finding.id];
    if (saved && saved.session_id) {
      const resume = el("button", "btn", "Continue in Claude Code");
      resume.type = "button";
      resume.addEventListener("click", async () => {
        try {
          const result = await api("/api/launch", { finding_id: finding.id, resume: true });
          toast(result.dry_run ? "Dry run: resume recorded" : "Resumed the investigation session");
        } catch (error) {
          toast(error.message);
        }
      });
      node.appendChild(resume);
    }
    return node;
  }

  function buildRow(finding) {
    const row = el("details", "row");
    row.dataset.id = finding.id;
    row.open = openRows.has(finding.id);
    row.addEventListener("toggle", () => { if (row.open) openRows.add(finding.id); else openRows.delete(finding.id); });

    const summary = el("summary");
    summary.appendChild(el("span", "pill " + finding.disposition, DISPOSITIONS[finding.disposition]));
    const title = el("div", "title");
    title.appendChild(el("b", "", finding.title));
    const badges = el("div", "badges");
    badges.appendChild(el("span", "mono", [finding.code, groupOf(finding)].filter(Boolean).join(" · ")));
    if (finding.route) badges.appendChild(el("span", "", "route: " + finding.route));
    const known = knownFor(finding);
    if (known) badges.appendChild(el("span", "pill good", KNOWN_LABEL[known.state] + (known.ticket ? " " + known.ticket : "")));
    if (state.investigations[finding.id]) badges.appendChild(el("span", "pill muted", "Investigated"));
    if (state.sumo.available && finding.sumo) {
      badges.appendChild(el("span", "pill muted", finding.sumo.total ? finding.sumo.total + " monitor" + (finding.sumo.total === 1 ? "" : "s") + " mention" : "No monitor mentions"));
    }
    title.appendChild(badges);
    const figures = el("div", "figures");
    figures.appendChild(el("span", "mono", finding.dollars != null ? money(finding.dollars) : finding.count + " " + finding.unit.replace(/^failed /, "")));
    figures.appendChild(el("span", "mono", finding.dollars != null ? finding.count + " " + finding.unit.replace(/^failed /, "") : finding.window_days + " d window"));
    summary.append(title, figures);
    row.appendChild(summary);

    const detail = el("div", "detail");
    if (finding.summary) detail.appendChild(el("p", "", finding.summary));
    detail.appendChild(actionsBlock(finding));

    const cols = el("div", "cols");
    const facts = el("dl", "facts");
    fact(facts, "Signature", finding.key, true);
    fact(facts, "Error text", finding.error_text, false);
    fact(facts, "Size", finding.stat, false);
    fact(facts, "Highlights", finding.highlights, true);
    fact(facts, "Next step from the service", finding.next_step, false);
    Object.keys(finding.helpful).forEach((source) => {
      const info = finding.helpful[source];
      if (info.found) fact(facts, "Helpful info (" + source + ")", info.text, false);
    });
    const left = block("Details");
    left.appendChild(facts);
    cols.append(left, monitorsBlock(finding));
    detail.appendChild(cols);

    if (finding.samples.length) {
      const samples = block("Samples");
      samples.appendChild(table(finding.sample_columns, finding.samples));
      detail.appendChild(samples);
    }
    if (finding.draft) {
      const draft = block(finding.draft.title ? finding.draft.title : "Draft");
      draft.appendChild(el("p", "note", { ops_handoff: "Ops handoff, not sent", ticket_draft: "Ticket draft, not created", biz_ops: "Biz-ops review, AI-chosen, not sent", dev_ticket: "Dev ticket, AI-chosen, not created" }[finding.draft.kind] || "Draft"));
      draft.appendChild(el("pre", "draft", finding.draft.body));
      const buttons = el("div", "actions");
      const copy = el("button", "btn", "Copy draft");
      copy.type = "button";
      copy.addEventListener("click", () => copyText(finding.draft.body, "Draft"));
      buttons.appendChild(copy);
      if (finding.draft.meta.duplicate_search_jql) {
        const jql = el("button", "btn", "Copy duplicate-check JQL");
        jql.type = "button";
        jql.addEventListener("click", () => copyText(finding.draft.meta.duplicate_search_jql, "JQL"));
        buttons.appendChild(jql);
      }
      draft.appendChild(buttons);
      detail.appendChild(draft);
    }
    if (finding.log) {
      const sub = el("details", "sub");
      sub.appendChild(el("summary", "", "Log evidence (as returned by the service)"));
      sub.appendChild(el("pre", "draft", finding.log));
      detail.appendChild(sub);
    }
    detail.appendChild(investigationBlock(finding));
    detail.appendChild(knownBlock(finding));
    row.appendChild(detail);
    return row;
  }

  function renderList() {
    const list = $("list");
    list.replaceChildren();
    if (!state.report) {
      const empty = el("div", "empty");
      empty.appendChild(el("b", "", "No report yet"));
      empty.appendChild(el("span", "", "Refresh runs failure_triage headless (about 4 minutes, about $0.35). To load a saved run instead:"));
      empty.appendChild(el("code", "mono", "python3 -m servicing_triage_ui import <file>"));
      list.appendChild(empty);
      return;
    }
    const findings = visibleFindings();
    if (!findings.length) {
      const hidden = state.report.findings.length - findings.length;
      const empty = el("div", "empty");
      empty.appendChild(el("b", "", "Nothing matches these filters"));
      empty.appendChild(el("span", "", hidden + " findings are hidden by the filters or by Hide known."));
      list.appendChild(empty);
      return;
    }
    findings.forEach((finding) => list.appendChild(buildRow(finding)));
  }

  function renderFooter() {
    const parts = ["Data in " + "~/.servicing-triage-ui", "ids, amounts and error text only"];
    if (state.sumo.available) parts.push("Sumo monitors: " + state.sumo.count + " from sumologic-config " + (state.sumo.sha || "") + " (" + (state.sumo.date || "") + ")");
    if (state.capabilities.dry_run) parts.push("DRY RUN: launch does not open a terminal");
    $("foot").textContent = parts.join(" · ");
  }

  function renderView() {
    renderFilters();
    renderList();
  }

  function render() {
    renderMeta();
    renderBanner();
    renderSummary();
    renderUnchecked();
    renderView();
    renderFooter();
  }

  async function load() {
    try {
      state = await api("/api/state");
    } catch (error) {
      toast("Could not load state: " + error.message);
      return;
    }
    const signature = JSON.stringify([state.report && state.report.fetched_at, state.known, state.investigations, state.jobs.map((job) => [job.id, job.status])]);
    if (signature !== lastSignature) {
      lastSignature = signature;
      render();
    } else {
      renderMeta();
      renderBanner();
    }
    clearTimeout(pollTimer);
    if (runningJobs().length) pollTimer = setTimeout(load, 3000);
  }

  $("refresh").addEventListener("click", async () => {
    try {
      await api("/api/refresh", { window_days: Number($("window").value) });
      toast("Refresh started");
      await load();
    } catch (error) {
      toast(error.message);
    }
  });
  $("search").addEventListener("input", (event) => { view.query = event.target.value; renderList(); });
  $("hide-known").addEventListener("change", (event) => { view.hideKnown = event.target.checked; renderList(); });
  setInterval(() => { if (state && runningJobs().length) renderBanner(); }, 1000);
  load();
})();
