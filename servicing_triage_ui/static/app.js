(() => {
  const TOKEN = document.querySelector('meta[name="triage-token"]').content;
  const $ = (id) => document.getElementById(id);
  const DISPOSITIONS = { bug: "Bug", ops: "Needs a person", review: "No playbook" };
  const SECTION_TITLES = { bug: "Bugs", ops: "Needs a person", review: "No playbook yet" };
  const SECTION_HINT = {
    bug: "A code or data defect. A ticket draft is attached.",
    ops: "Not a defect. Someone has to act on the loan or payment.",
    review: "Failures with no playbook. Decide whether one is needed."
  };
  const KNOWN_LABEL = { known: "Known", ticketed: "Ticketed", ignore: "Ignored" };
  const GROUPS = ["Payments", "Task queues", "Billing"];

  let state = null;
  let lastSignature = "";
  let pollTimer = null;
  let openedSeen = "";
  const view = { disposition: "all", group: "all", query: "", hideKnown: true };

  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const money = (value) => value.toLocaleString("en-US", { style: "currency", currency: "USD" });
  const wholeMoney = (value) => value.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
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
  const knownFor = (finding) => state.known[finding.id] || null;
  const isPinned = (finding) => state.pins.includes(finding.id);
  const attentionFor = (finding) => state.attention[finding.id] || null;
  const investigating = (finding) => runningJobs().some((job) => job.kind === "investigate" && job.finding_id === finding.id);

  function currentRoute() {
    const hash = location.hash.replace(/^#/, "");
    const found = /^\/f\/([0-9a-f]{12})$/.exec(hash);
    if (found) return { name: "finding", id: found[1] };
    if (hash === "/stats") return { name: "stats" };
    return { name: "list" };
  }

  async function act(label, work) {
    try {
      await work();
      if (label) toast(label);
      await load();
    } catch (error) {
      toast(error.message);
    }
  }

  function pinButton(finding) {
    const pinned = isPinned(finding);
    const button = el("button", "pin" + (pinned ? " on" : ""), pinned ? "★" : "☆");
    button.type = "button";
    button.setAttribute("aria-pressed", String(pinned));
    button.setAttribute("aria-label", pinned ? "Unpin this issue" : "Pin this issue");
    button.title = pinned ? "Unpin" : "Pin to the top of the list";
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      act(pinned ? "Unpinned" : "Pinned", () => api("/api/pin", { finding_id: finding.id, pinned: !pinned }));
    });
    return button;
  }

  function visibleFindings() {
    const query = view.query.toLowerCase();
    return state.report.findings.filter((finding) => {
      if (view.disposition !== "all" && finding.disposition !== view.disposition) return false;
      if (view.group !== "all" && groupOf(finding) !== view.group) return false;
      if (!isPinned(finding) && view.hideKnown && knownFor(finding)) return false;
      if (!query) return true;
      return [finding.title, finding.key, finding.code, finding.summary, finding.error_text].join(" ").toLowerCase().includes(query);
    });
  }

  function figuresOf(finding) {
    const unit = finding.unit.replace(/^failed /, "");
    return finding.dollars != null
      ? [money(finding.dollars), finding.count + " " + unit]
      : [finding.count + " " + unit, finding.window_days + " d window"];
  }

  function monitorPill(finding) {
    if (!state.sumo.available || !finding.sumo) return null;
    const total = finding.sumo.total;
    return el("span", "pill " + (total ? "monitor" : "gap"), total ? total + " monitor" + (total === 1 ? "" : "s") : "No monitor");
  }

  function badgesFor(finding) {
    const badges = el("div", "badges");
    badges.appendChild(el("span", "mono", [finding.code, groupOf(finding)].filter(Boolean).join(" · ")));
    if (finding.route) badges.appendChild(el("span", "", "route: " + finding.route));
    const attention = attentionFor(finding);
    if (investigating(finding)) badges.appendChild(el("span", "pill running", "Investigating"));
    else if (attention) badges.appendChild(el("span", "pill attn", attention.kind === "failed" ? "Investigation failed" : "Result ready"));
    else if (state.investigations[finding.id]) badges.appendChild(el("span", "pill muted", "Investigated"));
    const known = knownFor(finding);
    if (known) badges.appendChild(el("span", "pill good", KNOWN_LABEL[known.state] + (known.ticket ? " " + known.ticket : "")));
    const monitors = monitorPill(finding);
    if (monitors) badges.appendChild(monitors);
    return badges;
  }

  function buildRow(finding) {
    const row = el("div", "row " + finding.disposition + (attentionFor(finding) ? " attn" : ""));
    const body = el("div", "row-body");
    const link = el("a", "row-link", finding.title);
    link.href = "#/f/" + finding.id;
    body.append(link, badgesFor(finding));
    const [main, sub] = figuresOf(finding);
    const figures = el("div", "figures");
    figures.append(el("span", "mono", main), el("span", "mono", sub));
    row.append(pinButton(finding), body, figures);
    return row;
  }

  function sectionOf(name, title, hint, findings) {
    const section = el("section", "band " + name);
    const head = el("header", "band-head");
    const heading = el("div", "band-title");
    heading.append(el("h2", "", title), el("span", "count", String(findings.length)));
    head.appendChild(heading);
    const dollars = findings.reduce((sum, finding) => sum + (finding.dollars || 0), 0);
    head.appendChild(el("span", "soft band-hint", hint + (dollars ? " · " + wholeMoney(dollars) : "")));
    section.appendChild(head);
    const rows = el("div", "rows");
    findings.forEach((finding) => rows.appendChild(buildRow(finding)));
    section.appendChild(rows);
    return section;
  }

  function renderSections(container) {
    container.replaceChildren();
    const findings = visibleFindings();
    if (!findings.length) {
      const empty = el("div", "empty");
      empty.appendChild(el("b", "", "Nothing matches these filters"));
      empty.appendChild(el("span", "", state.report.findings.length + " findings in this report. Some are hidden by the filters or by Hide known."));
      container.appendChild(empty);
      return;
    }
    const pinned = findings.filter(isPinned);
    if (pinned.length) container.appendChild(sectionOf("pinned", "Pinned", "Kept at the top until you unpin them", pinned));
    Object.keys(SECTION_TITLES).forEach((name) => {
      const members = findings.filter((finding) => finding.disposition === name && !isPinned(finding));
      if (members.length) container.appendChild(sectionOf(name, SECTION_TITLES[name], SECTION_HINT[name], members));
    });
  }

  function summaryCards(report) {
    const node = el("section", "summary");
    node.setAttribute("aria-label", "Summary");
    const findings = report.findings;
    const count = (name) => findings.filter((finding) => finding.disposition === name).length;
    const open = findings.filter((finding) => !knownFor(finding)).length;
    const dollars = findings.reduce((sum, finding) => sum + (finding.dollars || 0), 0);
    const noMonitor = state.sumo.available ? findings.filter((finding) => finding.sumo && finding.sumo.total === 0).length : null;
    const cells = [
      [String(report.failures), "failures", ""],
      [wholeMoney(dollars), "payment dollars", ""],
      [String(count("bug")), count("bug") === 1 ? "bug" : "bugs", "bug"],
      [String(count("ops")), count("ops") === 1 ? "needs a person" : "need a person", "ops"],
      [String(count("review")), "no playbook", "review"],
      [String(open), "not marked known", ""]
    ];
    if (noMonitor !== null) cells.push([String(noMonitor), noMonitor === 1 ? "has no monitor" : "have no monitor", "gap"]);
    cells.forEach(([value, label, tone]) => {
      const cell = el("div", "stat " + tone);
      cell.append(el("span", "num", value), el("span", "lbl", label));
      node.appendChild(cell);
    });
    return node;
  }

  function attentionPanel(findings) {
    const items = findings.filter((finding) => attentionFor(finding));
    if (!items.length) return null;
    const panel = el("section", "attention");
    panel.setAttribute("aria-label", "Needs your attention");
    const head = el("div", "attention-head");
    head.append(el("h2", "", "Needs your attention"), el("span", "count", String(items.length)));
    panel.appendChild(head);
    items.forEach((finding) => {
      const attention = attentionFor(finding);
      const line = el("div", "attention-row");
      const link = el("a", "", finding.title);
      link.href = "#/f/" + finding.id;
      line.append(link, el("span", "soft", attention.kind === "failed" ? "Investigation failed: " + (attention.message || "") : "Investigation result is ready"));
      panel.appendChild(line);
    });
    return panel;
  }

  function chip(label, pressed, onClick) {
    const button = el("button", "chip", label);
    button.type = "button";
    button.setAttribute("aria-pressed", String(pressed));
    button.addEventListener("click", onClick);
    return button;
  }

  function toolbar(findings, onChange) {
    const bar = el("section", "toolbar");
    bar.setAttribute("aria-label", "Filters");
    const dispositions = el("div", "chips");
    [["all", "All (" + findings.length + ")"]].concat(
      Object.keys(DISPOSITIONS).map((key) => [key, DISPOSITIONS[key] + " (" + findings.filter((f) => f.disposition === key).length + ")"]))
      .forEach(([key, label]) => dispositions.appendChild(chip(label, view.disposition === key, () => { view.disposition = key; renderPage(); })));
    const areas = el("div", "chips");
    [["all", "All areas"]].concat(GROUPS.map((name) => [name, name + " (" + findings.filter((f) => groupOf(f) === name).length + ")"]))
      .forEach(([key, label]) => areas.appendChild(chip(label, view.group === key, () => { view.group = key; renderPage(); })));
    const tools = el("div", "tools");
    const search = el("input");
    search.type = "search";
    search.id = "search";
    search.placeholder = "Search code, task or text";
    search.setAttribute("aria-label", "Search findings");
    search.value = view.query;
    search.addEventListener("input", (event) => { view.query = event.target.value; onChange(); });
    const label = el("label", "check");
    const box = el("input");
    box.type = "checkbox";
    box.id = "hide-known";
    box.checked = view.hideKnown;
    box.addEventListener("change", (event) => { view.hideKnown = event.target.checked; onChange(); });
    label.append(box, document.createTextNode(" Hide known"));
    tools.append(search, label);
    bar.append(dispositions, areas, tools);
    return bar;
  }

  function uncheckedPanel(items) {
    if (!items.length) return null;
    const panel = el("section", "panel warn");
    panel.appendChild(el("h2", "", "Sensors that did not run"));
    const list = el("ul");
    items.forEach((item) => list.appendChild(el("li", "", item.name + ": " + item.reason)));
    panel.appendChild(list);
    return panel;
  }

  function emptyReport() {
    const empty = el("div", "empty");
    empty.appendChild(el("b", "", "No report yet"));
    empty.appendChild(el("span", "", "Refresh runs failure_triage headless (about 4 minutes, about $0.35). To load a saved run instead:"));
    empty.appendChild(el("code", "mono", "python3 -m servicing_triage_ui import <file>"));
    return empty;
  }

  function renderList(page) {
    if (!state.report) {
      page.appendChild(emptyReport());
      return;
    }
    const findings = state.report.findings;
    [attentionPanel(findings), summaryCards(state.report), uncheckedPanel(state.report.unchecked)].forEach((node) => node && page.appendChild(node));
    const sections = el("div", "sections");
    page.append(toolbar(findings, () => renderSections(sections)), sections);
    renderSections(sections);
  }

  /* ---------- finding view ---------- */

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

  function panel(title, tone) {
    const node = el("section", "card" + (tone ? " " + tone : ""));
    node.appendChild(el("h2", "", title));
    return node;
  }

  function fact(list, term, value, mono) {
    if (!value) return;
    const group = el("div");
    group.append(el("dt", "", term), el("dd", mono ? "mono" : "", value));
    list.appendChild(group);
  }

  function monitorsCard(finding) {
    const node = panel("Sumo monitors that mention this", "monitors");
    if (!state.sumo.available) {
      node.appendChild(el("p", "note", "No monitor index. Run: python3 -m servicing_triage_ui sync-monitors"));
      return node;
    }
    const sumo = finding.sumo;
    if (!sumo || sumo.total === 0) {
      node.appendChild(el("p", "gap-note", "No monitor definition mentions this code, text or task."));
    } else {
      sumo.monitors.forEach((monitor) => {
        const card = el("div", "monitor");
        card.appendChild(el("b", "", monitor.name));
        const meta = el("div", "meta");
        meta.appendChild(el("span", "tag", "matched on " + monitor.matched_on.join(", ")));
        if (monitor.priority) meta.appendChild(el("span", "tag", monitor.priority));
        if (monitor.window) meta.appendChild(el("span", "tag", monitor.window + " window"));
        monitor.channels.forEach((channel) => meta.appendChild(el("span", "tag mono", "#" + channel)));
        if (monitor.incidentio) meta.appendChild(el("span", "tag", "incident.io"));
        card.appendChild(meta);
        node.appendChild(card);
      });
      if (sumo.total > sumo.monitors.length) node.appendChild(el("p", "note", (sumo.total - sumo.monitors.length) + " more not shown."));
    }
    node.appendChild(el("p", "note", "A mention is not coverage. This reads monitor definitions at " + (state.sumo.sha || "unknown") + ", not fired alerts."));
    return node;
  }

  function investigationCard(finding) {
    const node = panel("Investigation", "investigation");
    const attention = attentionFor(finding);
    const running = investigating(finding);
    const saved = state.investigations[finding.id];
    if (attention && attention.kind === "failed") node.appendChild(el("p", "alert", "The last investigation failed: " + (attention.message || "unknown error")));
    if (running) node.appendChild(el("p", "running-note", "Running headless, read-only tools only. Takes a few minutes. This page updates when it finishes."));
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

  function knownCard(finding) {
    const node = panel("Known issue");
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
    save.addEventListener("click", () => act("Saved", () => api("/api/known", { finding_id: finding.id, state: select.value, note: note.value, ticket: ticket.value })));
    form.append(select, note, ticket, save);
    node.appendChild(form);
    node.appendChild(el("p", "note", "Stored on this machine only (" + (current ? "updated " + ago(current.updated_at) + " by " + current.by : "not marked") + ")."));
    return node;
  }

  function actionsBar(finding) {
    const node = el("div", "actions-bar");
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
    const running = investigating(finding);
    const run = el("button", "btn", running ? "Investigating..." : state.investigations[finding.id] ? "Run again" : "Run investigation");
    run.type = "button";
    run.disabled = running || !state.capabilities.headless;
    run.addEventListener("click", () => act("Investigation started", () => api("/api/investigate", { finding_id: finding.id })));
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

  function draftCard(finding) {
    const draft = panel(finding.draft.title ? finding.draft.title : "Draft", "draft-card");
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
    return draft;
  }

  function renderFinding(page, id) {
    const finding = state.report && state.report.findings.find((candidate) => candidate.id === id);
    const back = el("a", "back", "← All findings");
    back.href = "#/";
    page.appendChild(back);
    if (!finding) {
      const empty = el("div", "empty");
      empty.appendChild(el("b", "", "This finding is not in the current report"));
      empty.appendChild(el("span", "", "A refresh replaces the report. Findings that stopped failing no longer appear."));
      page.appendChild(empty);
      return;
    }
    const attention = attentionFor(finding);
    if (attention && openedSeen !== finding.id + attention.token) {
      openedSeen = finding.id + attention.token;
      api("/api/seen", { finding_id: finding.id }).then(() => load()).catch(() => {});
    }

    const hero = el("section", "hero " + finding.disposition);
    const top = el("div", "hero-top");
    const heading = el("div", "hero-heading");
    const tags = el("div", "badges");
    tags.appendChild(el("span", "pill " + finding.disposition, DISPOSITIONS[finding.disposition]));
    tags.appendChild(el("span", "mono", [finding.code, groupOf(finding)].filter(Boolean).join(" · ")));
    if (finding.route) tags.appendChild(el("span", "", "route: " + finding.route));
    const known = knownFor(finding);
    if (known) tags.appendChild(el("span", "pill good", KNOWN_LABEL[known.state] + (known.ticket ? " " + known.ticket : "")));
    const monitors = monitorPill(finding);
    if (monitors) tags.appendChild(monitors);
    heading.append(tags, el("h1", "", finding.title));
    const [main, sub] = figuresOf(finding);
    const figures = el("div", "hero-figures");
    figures.append(el("span", "big mono", main), el("span", "mono soft", sub));
    top.append(pinButton(finding), heading, figures);
    hero.appendChild(top);
    page.appendChild(hero);

    if (attention && attention.kind === "result") {
      page.appendChild(el("div", "banner attn-banner", "The investigation finished. The result is in the Investigation section below."));
    }

    if (finding.summary) {
      const what = panel("What happened", "what");
      what.appendChild(el("p", "lead", finding.summary));
      if (finding.highlights) what.appendChild(el("p", "mono soft", finding.highlights));
      page.appendChild(what);
    }
    page.appendChild(actionsBar(finding));

    const cols = el("div", "cols");
    const facts = el("dl", "facts");
    fact(facts, "Signature", finding.key, true);
    fact(facts, "Error text", finding.error_text, false);
    fact(facts, "Size", finding.stat, false);
    fact(facts, "Next step from the service", finding.next_step, false);
    Object.keys(finding.helpful).forEach((source) => {
      const info = finding.helpful[source];
      if (info.found) fact(facts, "Helpful info (" + source + ")", info.text, false);
    });
    const details = panel("Details");
    details.appendChild(facts);
    cols.append(monitorsCard(finding), details);
    page.appendChild(cols);

    if (finding.samples.length) {
      const samples = panel("Samples");
      samples.appendChild(table(finding.sample_columns, finding.samples));
      page.appendChild(samples);
    }
    if (finding.draft) page.appendChild(draftCard(finding));
    if (finding.log) {
      const evidence = panel("Log evidence", "evidence");
      evidence.appendChild(el("p", "note", "As returned by the service."));
      evidence.appendChild(el("pre", "draft", finding.log));
      page.appendChild(evidence);
    }
    page.appendChild(investigationCard(finding));
    page.appendChild(knownCard(finding));
  }

  /* ---------- stats view ---------- */

  function changeChip(row) {
    if (!row.change_text) return null;
    const percent = row.change_percent;
    if (percent === null) return el("span", "delta flat", row.change_text);
    if (percent === 0) return el("span", "delta flat", "same");
    const up = percent > 0;
    const tone = row.failure ? (up ? "bad" : "good") : "flat";
    const chipNode = el("span", "delta " + tone, (up ? "▲ " : "▼ ") + Math.abs(percent) + "%");
    chipNode.title = row.change_text;
    return chipNode;
  }

  function statsRow(row) {
    const line = el("div", "stat-row" + (row.failure ? " failure" : ""));
    line.appendChild(el("span", "stat-label", row.label));
    const numbers = el("span", "stat-numbers");
    numbers.appendChild(el("span", "stat-count mono", row.count === null ? row.raw : row.count.toLocaleString("en-US")));
    if (row.dollars !== null) numbers.appendChild(el("span", "mono soft", money(row.dollars)));
    line.appendChild(numbers);
    const chipNode = changeChip(row);
    line.appendChild(chipNode || el("span"));
    const extra = el("div", "stat-extra");
    row.breakdown.forEach((part) => extra.appendChild(el("span", "tag mono", part.name + " " + part.count)));
    if (row.follow_up && row.count) {
      const link = el("a", "follow", "Open failures");
      link.href = "#/";
      link.title = row.follow_up;
      extra.appendChild(link);
    }
    if (extra.childNodes.length) line.appendChild(extra);
    return line;
  }

  function renderStats(page) {
    const stats = state.stats;
    if (!stats) {
      const empty = el("div", "empty");
      empty.appendChild(el("b", "", "No stats yet"));
      empty.appendChild(el("span", "", "Refresh stats runs daily_stats headless (under a minute, about $0.35)."));
      page.appendChild(empty);
      return;
    }
    const head = el("section", "stats-head");
    head.append(el("h2", "", "Servicing stats for " + (stats.day || "the day") + " (UTC)"), el("span", "soft", "Change is against the day before. Fetched " + ago(stats.fetched_at) + "."));
    page.appendChild(head);
    const grid = el("div", "stat-grid");
    stats.sections.forEach((section) => {
      const card = el("section", "card stat-card" + (section.rows.some((row) => row.follow_up && row.count) ? " flagged" : ""));
      card.appendChild(el("h2", "", section.name));
      section.rows.forEach((row) => card.appendChild(statsRow(row)));
      grid.appendChild(card);
    });
    page.appendChild(grid);
    const unchecked = uncheckedPanel(stats.unchecked);
    if (unchecked) page.appendChild(unchecked);
    stats.notes.forEach((note) => page.appendChild(el("p", "note", note)));
  }

  /* ---------- chrome ---------- */

  function renderChrome(route) {
    const onStats = route.name === "stats";
    $("tab-failures").classList.toggle("on", !onStats);
    $("tab-stats").classList.toggle("on", onStats);
    $("run-failures").hidden = onStats;
    $("run-stats").hidden = !onStats;
    const report = state.report;
    const source = onStats ? state.stats : report;
    if (onStats) {
      $("meta").textContent = source ? "Fetched " + ago(source.fetched_at) : "No stats yet";
    } else {
      $("meta").textContent = report
        ? "Last " + report.window_days + (report.window_days === 1 ? " day" : " days") + ", fetched " + ago(report.fetched_at) + " (" + report.source + ")"
        : "No report yet";
    }
    const refreshing = runningJobs().some((job) => job.kind === "refresh");
    const refresh = $("refresh");
    refresh.disabled = refreshing || !state.capabilities.headless;
    refresh.textContent = refreshing ? "Refreshing..." : "Refresh";
    refresh.title = state.capabilities.headless ? "Runs failure_triage headless. About 4 minutes and about $0.35." : "claude CLI not found";
    const statsRunning = runningJobs().some((job) => job.kind === "stats");
    const statsButton = $("refresh-stats");
    statsButton.disabled = statsRunning || !state.capabilities.headless;
    statsButton.textContent = statsRunning ? "Refreshing..." : "Refresh stats";
    const waiting = Object.keys(state.attention).length;
    $("tab-failures").textContent = waiting ? "Failures (" + waiting + " to look at)" : "Failures";
    document.title = (waiting ? "(" + waiting + ") " : "") + "Servicing Triage";
    renderBanner();
    const parts = ["Data in ~/.servicing-triage-ui", "ids, amounts and error text only"];
    if (state.sumo.available) parts.push("Sumo monitors: " + state.sumo.count + " from sumologic-config " + (state.sumo.sha || "") + " (" + (state.sumo.date || "") + ")");
    if (state.capabilities.dry_run) parts.push("DRY RUN: launch does not open a terminal");
    $("foot").textContent = parts.join(" · ");
  }

  function renderBanner() {
    const banner = $("banner");
    const running = runningJobs();
    const failed = state.jobs.find((job) => job.status === "error" && job.kind !== "investigate" && Date.now() / 1000 - (job.finished || 0) < 600);
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

  function renderPage() {
    const route = currentRoute();
    const focused = document.activeElement && document.activeElement.id === "search";
    const page = $("page");
    page.replaceChildren();
    renderChrome(route);
    if (route.name === "stats") renderStats(page);
    else if (route.name === "finding") renderFinding(page, route.id);
    else renderList(page);
    if (focused && $("search")) {
      const search = $("search");
      search.focus();
      search.setSelectionRange(search.value.length, search.value.length);
    }
  }

  async function load() {
    try {
      state = await api("/api/state");
    } catch (error) {
      toast("Could not load state: " + error.message);
      return;
    }
    const signature = JSON.stringify([
      state.report && state.report.fetched_at, state.stats && state.stats.fetched_at, state.known, state.investigations,
      state.pins, state.attention, state.jobs.map((job) => [job.id, job.status])
    ]);
    const editing = document.activeElement && document.activeElement.closest("#page") && /^(INPUT|SELECT|TEXTAREA)$/.test(document.activeElement.tagName) && document.activeElement.id !== "search";
    if (signature !== lastSignature && !editing) {
      lastSignature = signature;
      renderPage();
    } else {
      renderChrome(currentRoute());
    }
    clearTimeout(pollTimer);
    if (runningJobs().length) pollTimer = setTimeout(load, 3000);
  }

  window.addEventListener("hashchange", () => {
    if (!state) return;
    lastSignature = "";
    renderPage();
    window.scrollTo(0, 0);
  });
  $("page").addEventListener("focusout", () => setTimeout(load, 250));
  $("refresh").addEventListener("click", () => act("Refresh started", () => api("/api/refresh", { window_days: Number($("window").value) })));
  $("refresh-stats").addEventListener("click", () => act("Stats refresh started", () => api("/api/stats", { day: $("stats-day").value })));
  setInterval(() => { if (state && runningJobs().length) renderBanner(); }, 1000);
  load();
})();
