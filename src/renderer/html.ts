// Matches Ruby's escape_html (no apostrophe encoding)
function escHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

import { readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  costUsd,
  humanText,
  isHumanPrompt,
  isTaskNotification,
  taskNotificationSummary,
  toolResults,
  toolUses,
} from "../token";
import type { ContentBlock, Node } from "../types";

const __dirname = dirname(fileURLToPath(import.meta.url));

function readAsset(name: string): string {
  return readFileSync(join(__dirname, name), "utf-8");
}

const ROW_HEIGHT = 32;
const MIN_LABEL_PX = 60;
const CONTEXT_LIMIT = 200_000;

const LEGEND_ITEMS: ReadonlyArray<readonly [string, string]> = [
  ["bar-c-human", "User prompt"],
  ["bar-c-task", "Task callback"],
  ["bar-c-assistant", "Assistant response"],
  ["bar-c-tool", "Tool call"],
  ["bar-c-sidechain", "Subagent turn"],
  ["bar-compaction", "Compaction"],
];

interface SessionMetrics {
  assistantNodes: Node[];
  prompts: number;
  allPrompts: number;
  tasks: number;
  turns: number;
  sub: number;
  marginal: number;
  cached: number;
  cacheNew: number;
  output: number;
  totalCost: number;
  totalInput: number;
  hitRate: number | null;
  compactions: number;
  pressure: number;
  models: string;
}

export class Html {
  private readonly canvasWidth: number;
  // Set during render():
  private rereadFiles = new Map<string, number>();
  private threadCount = 0;
  private threadNumbers = new Map<string | null, number>();
  private agentLabels = new Map<string, string>();
  private hmCount = 0;

  constructor(canvasWidth = 1200) {
    this.canvasWidth = canvasWidth;
  }

  render(nodes: Node[]): string {
    const allFlat = this.flatten(nodes);
    const all = allFlat.filter((n) => (n.w ?? 0) > 1);
    const maxDepth = all.reduce((max, n) => Math.max(max, n.depth ?? 0), 0);
    const flameHeight = (maxDepth + 2) * ROW_HEIGHT; // +1 for TOTAL bar at bottom
    const totalTop = (maxDepth + 1) * ROW_HEIGHT;
    const totalTokens = nodes.reduce((s, n) => s + (n.subtreeTokens ?? 0), 0);
    const totalCost = nodes.reduce((s, n) => s + (n.subtreeCost ?? 0), 0);
    const totalTip = escapeJs(escHtml(this.totalSummary(allFlat)));
    this.rereadFiles = this.buildRereadMap(all);
    this.threadCount = nodes.length;
    this.threadNumbers = new Map();
    all
      .filter((n) => n.depth === 0)
      .forEach((n, i) => {
        this.threadNumbers.set(n.token.uuid, i + 1);
      });
    this.agentLabels = new Map();
    for (const n of all) {
      const id = n.token.agentId;
      if (id && !this.agentLabels.has(id)) {
        this.agentLabels.set(id, `A${this.agentLabels.size + 1}`);
      }
    }
    this.assignAlternation(nodes);
    this.hmCount = nodes.length; // overridden by heatmapHtml after grouping
    const tokenTotalLbl = `TOTAL &middot; ${fmt(totalTokens)} tokens`;
    const costTotalLbl = `TOTAL &middot; ${fmtCost(totalCost)}`;

    const cssText = readAsset("html.css");
    const jsText = this.js();

    return `<!DOCTYPE html>
<html data-theme="dark">
<head>
<meta charset="utf-8">
<title>Token Lens \u00b7 Brickell Research</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,400;0,600;1,400&display=swap');
${cssText}
</style>
</head>
<body>
<div class="header">
  <div>
    <div class="summary">${this.summaryText(allFlat)}</div>
    <div class="legend" id="legend" style="display:none">${this.legendHtml()}</div>
  </div>
  <div class="header-btns">
    <button class="theme-btn" id="theme-btn" onclick="toggleTheme()">&#x25D0; Light</button>
    <button class="summary-btn" id="summary-btn" onclick="toggleSummary()">&#x2261; Summary</button>
    <button class="cost-btn" id="cost-btn" onclick="toggleCostView()">$ Cost view</button>
    <button class="reset-btn" id="reset-btn" onclick="resetZoom()">&#x21A9; Reset zoom</button>
  </div>
</div>
${this.heatmapHtml(nodes)}
<div id="hm-back" class="hm-back" style="display:none" onclick="closePrompt()">\u2190 All prompts</div>
<div class="flame-wrap" id="flame-wrap" style="display:none">
<div class="flame" style="width:${this.canvasWidth}px;height:${flameHeight}px">
<div class="bar total-bar" style="left:0%;width:100%;top:${totalTop}px" data-ox="0" data-ow="${this.canvasWidth}" data-cx="0" data-cw="${this.canvasWidth}" onmouseover="tip('${totalTip}')" onmouseout="tip('')" onclick="if(hmActiveIdx<0)unzoom()"><span class="lbl total-lbl" id="total-lbl" data-token-text="${tokenTotalLbl}" data-cost-text="${costTotalLbl}">${tokenTotalLbl}</span></div>
${all.map((n) => this.barHtml(n)).join("\n")}
</div>
</div>
<div id="ftip" class="floattip"></div>
<div id="tip" class="tip"><span class="tip-label">Hover for details &middot; Click to zoom</span></div>
${this.sessionSummaryHtml(allFlat)}
<script>
${jsText}
</script>
</body>
</html>`;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private flatten(nodes: Node[]): Node[] {
    return nodes.flatMap((n) => [n, ...this.flatten(n.children)]);
  }

  private pct(val: number): string {
    return ((val / this.canvasWidth) * 100.0).toFixed(4);
  }

  private barHtml(node: Node): string {
    const t = node.token;
    const lbl = escHtml(this.label(node));
    const clbl = this.costLabel(node);
    const tip = escHtml(this.tooltip(node));
    const left = this.pct(node.x ?? 0);
    const width = this.pct(node.w ?? 0);
    const lblHidden = (node.w ?? 0) < MIN_LABEL_PX ? ` style="display:none"` : "";
    let extraClass = ` ${this.colorClass(node)}`;
    if (node.alt) extraClass += " bar-alt";
    if (this.rereadBar(node)) extraClass += " bar-reread";
    // is_compaction on assistant turns is for summary counting only; color is set via colorClass on the user prompt
    if (!t.isCompaction && this.contextPressure(node)) extraClass += " bar-pressure";
    const ftip = escHtml(this.tokenSummary(node));
    let mouseover: string;
    if (isTaskNotification(t)) {
      const summary = taskNotificationSummary(t) || "Task callback";
      mouseover = `tip('${escapeJs(tip)}','${escHtml(escapeJs(summary))}')`;
    } else if (isHumanPrompt(t)) {
      mouseover = `tip('${escapeJs(tip)}','${escHtml(escapeJs(humanText(t)))}')`;
    } else {
      mouseover = `tip('${escapeJs(tip)}')`;
    }
    const badge = this.rereadBar(node) ? `<span class="warn-badge">\u26a0</span>` : "";
    return `<div class="bar${extraClass}" style="left:${left}%;width:calc(${width}% + 1px);top:${node.y ?? 0}px" data-ox="${node.x ?? 0}" data-ow="${node.w ?? 0}" data-cx="${node.costX ?? 0}" data-cw="${node.costW ?? 0}" data-token-lbl="${lbl}" data-cost-lbl="${clbl}" data-ftip="${ftip}" onmouseover="${mouseover}" onmouseout="tip('')" onclick="zoom(this)"><span class="lbl"${lblHidden}>${lbl}</span>${badge}</div>`;
  }

  private buildRereadMap(all: Node[]): Map<string, number> {
    const counts = new Map<string, number>();
    for (const node of all) {
      for (const tu of toolUses(node.token)) {
        if (!["Read", "Write", "Edit"].includes(tu.name ?? "")) continue;
        const path = String(tu.input?.["file_path"] ?? "");
        if (path.length > 0) {
          counts.set(path, (counts.get(path) ?? 0) + 1);
        }
      }
    }
    const result = new Map<string, number>();
    for (const [k, v] of counts) {
      if (v > 1) result.set(k, v);
    }
    return result;
  }

  private tokenSummary(node: Node): string {
    const t = node.token;
    const tok = fmt(node.subtreeTokens ?? 0);
    const cost = (node.subtreeCost ?? 0) > 0 ? ` \u00b7 ${fmtCost(node.subtreeCost ?? 0)}` : "";
    if (isTaskNotification(t)) {
      const summary = taskNotificationSummary(t) || "Task callback";
      const nameMatch = summary.match(/Agent "([^"]+)"/);
      const name = nameMatch ? nameMatch[1] : summary;
      return `\u21a9 ${name} \u00b7 ${tok} tokens${cost}`;
    } else if (isHumanPrompt(t)) {
      const num = this.threadNumbers.get(t.uuid);
      return num ? `Thread ${num} \u00b7 ${tok} tokens${cost}` : `${tok} tokens${cost}`;
    } else if (t.isSidechain) {
      return `[${modelShort(t.model)}] ${tok} tokens${cost}`;
    } else {
      return `${tok} tokens${cost}`;
    }
  }

  private rereadBar(node: Node): boolean {
    return toolUses(node.token).some((tu) => {
      if (!["Read", "Write", "Edit"].includes(tu.name ?? "")) return false;
      const path = String(tu.input?.["file_path"] ?? "");
      return this.rereadFiles.has(path);
    });
  }

  private toolResultTokens(node: Node): number {
    const uses = toolUses(node.token);
    if (uses.length === 0) return 0;
    const userChild = node.children.find(
      (c) => c.token.role === "user" && toolResults(c.token).length > 0,
    );
    if (!userChild) return 0;
    let chars = 0;
    for (const tu of uses) {
      const results = toolResults(userChild.token);
      const tr = results.find(
        (r) => (r as unknown as Record<string, unknown>)["tool_use_id"] === tu.id,
      );
      if (!tr) continue;
      const content = Array.isArray(tr.content)
        ? tr.content
        : tr.content != null
          ? [tr.content]
          : [];
      for (const c of content) {
        if (typeof c === "object" && c !== null && (c as Record<string, unknown>)["text"] != null) {
          chars += String((c as Record<string, unknown>)["text"]).length;
        } else {
          chars += String(c).length;
        }
      }
    }
    return Math.floor(chars / 4);
  }

  private computeSessionMetrics(all: Node[]): SessionMetrics {
    const anodes = all.filter((n) => n.token.role === "assistant");
    const rawInput = anodes.reduce((s, n) => s + n.token.inputTokens, 0);
    const cached = anodes.reduce((s, n) => s + n.token.cacheReadTokens, 0);
    const cacheNew = anodes.reduce((s, n) => s + n.token.cacheCreationTokens, 0);
    const totalInput = rawInput + cached + cacheNew;
    const totalCost = anodes.reduce((s, n) => s + costUsd(n.token), 0);
    const hitRate = totalInput > 0 && cached > 0 ? (cached / totalInput) * 100 : null;
    const models = [
      ...new Set(
        anodes
          .map((n) => n.token.model)
          .filter(Boolean)
          .map((m) => modelShort(m)),
      ),
    ].join(", ");

    return {
      assistantNodes: anodes,
      prompts: all.filter((n) => isHumanPrompt(n.token) && !isTaskNotification(n.token)).length,
      allPrompts: all.filter((n) => isHumanPrompt(n.token)).length,
      tasks: all.filter((n) => isTaskNotification(n.token)).length,
      turns: anodes.filter((n) => !n.token.isSidechain).length,
      sub: anodes.filter((n) => n.token.isSidechain).length,
      marginal: anodes.reduce((s, n) => s + n.token.marginalInputTokens, 0),
      cached,
      cacheNew,
      output: anodes.reduce((s, n) => s + n.token.outputTokens, 0),
      totalCost,
      totalInput,
      hitRate,
      compactions: all.filter(
        (n) =>
          isHumanPrompt(n.token) &&
          humanText(n.token).startsWith("This session is being continued"),
      ).length,
      pressure: anodes.filter((n) => this.contextPressure(n)).length,
      models,
    };
  }

  private computeDuration(all: Node[]): string | null {
    const timestamps = all
      .map((n) => n.token.timestamp)
      .filter(Boolean)
      .sort() as string[];
    if (timestamps.length < 2) return null;
    try {
      const first = new Date(timestamps[0]);
      const last = new Date(timestamps[timestamps.length - 1]);
      const secs = Math.floor((last.getTime() - first.getTime()) / 1000);
      return secs > 0 ? fmtDuration(secs) : null;
    } catch {
      return null;
    }
  }

  private summaryText(all: Node[]): string {
    const m = this.computeSessionMetrics(all);
    const parts: (string | null)[] = [];
    if (this.threadCount > 1) parts.push(`${this.threadCount} threads`);
    parts.push(`${m.prompts} ${m.prompts === 1 ? "prompt" : "prompts"}`);
    if (m.tasks > 0) {
      parts.push(`${m.tasks} ${m.tasks === 1 ? "task callback" : "task callbacks"}`);
    }
    parts.push(`${m.turns} main ${m.turns === 1 ? "turn" : "turns"}`);
    if (m.sub > 0) {
      parts.push(`${m.sub} subagent ${m.sub === 1 ? "turn" : "turns"}`);
    }
    parts.push(this.computeDuration(all));
    if (m.marginal > 0) parts.push(`fresh input: ${fmt(m.marginal)}`);
    if (m.cached > 0) parts.push(`cached input: ${fmt(m.cached)}`);
    if (m.cacheNew > 0) parts.push(`written to cache: ${fmt(m.cacheNew)}`);
    if (m.hitRate != null) parts.push(`cache hit: ${Math.round(m.hitRate)}%`);
    if (m.output > 0) parts.push(`output: ${fmt(m.output)}`);
    if (m.totalCost > 0) parts.push(fmtCost(m.totalCost));
    return parts.filter(Boolean).join(" &middot; ");
  }

  private totalSummary(all: Node[]): string {
    const m = this.computeSessionMetrics(all);
    const parts: string[] = [];
    if (m.marginal > 0) parts.push(`fresh input: ${fmt(m.marginal)}`);
    if (m.cached > 0) parts.push(`cached input: ${fmt(m.cached)}`);
    if (m.cacheNew > 0) parts.push(`written to cache: ${fmt(m.cacheNew)}`);
    if (m.output > 0) parts.push(`output: ${fmt(m.output)}`);
    if (m.totalCost > 0) parts.push(`cost: ${fmtCost(m.totalCost)}`);
    return parts.join(" | ");
  }

  private threadSeparators(all: Node[]): string {
    const roots = all.filter((n) => n.depth === 0);
    if (roots.length <= 1) return "";
    // Emit a vertical line at the right edge of each thread (except the last)
    return roots
      .slice(0, -1)
      .map((n) => {
        const rightX = (n.x ?? 0) + (n.w ?? 0);
        const pctVal = this.pct(rightX);
        return `<div class="thread-sep" style="left:${pctVal}%"></div>`;
      })
      .join("\n");
  }

  private assignAlternation(siblings: Node[]): void {
    siblings.forEach((node, i) => {
      node.alt = i % 2 === 1;
      this.assignAlternation(node.children);
    });
  }

  private legendHtml(): string {
    return LEGEND_ITEMS.map(
      ([cssClass, lbl]) =>
        `<span class="legend-item"><span class="legend-swatch ${cssClass}"></span>${lbl}</span>`,
    ).join("");
  }

  private colorClass(node: Node): string {
    const t = node.token;
    if (isTaskNotification(t)) return "bar-c-task";
    if (t.isSidechain) return "bar-c-sidechain";
    if (isHumanPrompt(t) && humanText(t).startsWith("This session is being continued"))
      return "bar-compaction";
    if (isHumanPrompt(t)) return "bar-c-human";
    switch (t.role) {
      case "user":
        return "bar-c-user";
      case "assistant":
        return toolUses(t).length > 0 ? "bar-c-tool" : "bar-c-assistant";
      default:
        return "bar-c-user";
    }
  }

  private label(node: Node): string {
    const t = node.token;
    if (isTaskNotification(t)) {
      const summary = taskNotificationSummary(t) || "Task callback";
      const nameMatch = summary.match(/Agent "([^"]+)"/);
      const name = nameMatch ? nameMatch[1] : summary;
      return `\u21a9 ${name}`;
    } else if (isHumanPrompt(t)) {
      return humanText(t);
    } else if (t.role === "assistant" && toolUses(t).length > 0) {
      const uses = toolUses(t);
      let toolStr: string;
      if (uses.length === 1) {
        const brief = this.toolInput(uses[0], "brief");
        toolStr = brief.length === 0 ? (uses[0].name ?? "") : `${uses[0].name}: ${brief}`;
      } else {
        toolStr = uses.map((u) => u.name ?? "").join(", ");
      }
      const badge = t.isSidechain && t.agentId ? this.agentLabels.get(t.agentId) : undefined;
      return badge ? `[${badge}] ${toolStr}` : toolStr;
    } else if (t.role === "assistant") {
      let prefix: string;
      if (t.isSidechain) {
        const agentLbl = t.agentId ? this.agentLabels.get(t.agentId) : undefined;
        prefix = agentLbl
          ? `[${modelShort(t.model)} \u00b7 ${agentLbl}] `
          : `[${modelShort(t.model)}] `;
      } else {
        prefix = "";
      }
      const textBlock = t.content.find(
        (c): c is ContentBlock => typeof c === "object" && c !== null && c.type === "text",
      );
      const text = (textBlock?.text ?? "").trim();
      return text.length > 0
        ? `${prefix}${text}`
        : `${prefix}response \u00b7 out: ${fmt(t.outputTokens)}`;
    } else {
      return t.role ?? "";
    }
  }

  private tooltip(node: Node): string {
    const t = node.token;
    const parts: string[] = [];
    if (isHumanPrompt(t)) {
      // tip bar shows only the prompt text (via 2nd arg); no redundant stats here
    } else {
      parts.push(`${fmt(node.subtreeTokens ?? 0)} tokens`);
      if (t.model) parts.push(t.model);
      if (t.marginalInputTokens > 0) parts.push(`fresh input: ${fmt(t.marginalInputTokens)}`);
      if (t.cacheReadTokens > 0) parts.push(`cached input: ${fmt(t.cacheReadTokens)}`);
      if (t.cacheCreationTokens > 0) parts.push(`written to cache: ${fmt(t.cacheCreationTokens)}`);
      parts.push(`output: ${fmt(t.outputTokens)}`);
      const tokenCost = costUsd(t);
      if (tokenCost > 0) parts.push(`cost: ${fmtCost(tokenCost)}`);
      for (const tool of toolUses(t)) {
        const detail = this.toolInput(tool, "detail");
        if (detail.length > 0) parts.push(detail);
      }
      const resultTok = this.toolResultTokens(node);
      if (resultTok > 0) parts.push(`result: ~${fmt(resultTok)} tokens`);
      if (t.isSidechain) parts.push("subagent");
      if (t.agentId) parts.push(`agent: ${t.agentId}`);
      for (const tu of toolUses(t)) {
        if (!["Read", "Write", "Edit"].includes(tu.name ?? "")) continue;
        const path = String(tu.input?.["file_path"] ?? "");
        const count = this.rereadFiles.get(path);
        if (count !== undefined) {
          parts.push(`\u26a0 ${basename(path)} accessed ${count}x in session`);
        }
      }
    }
    return parts.join(" | ");
  }

  private toolInput(tool: ContentBlock, format: "brief" | "detail"): string {
    const input = (tool.input ?? {}) as Record<string, unknown>;
    const getCmd = (): string => {
      const raw = String(input["command"] ?? "").trim();
      return raw.replace(/^source[^\n&]+&&\s*rvm[^\n&]+&&\s*/, "");
    };
    switch (tool.name) {
      case "Bash":
        return format === "brief" ? getCmd() : truncate(getCmd(), 100);
      case "Read":
      case "Write":
      case "Edit":
        return format === "brief"
          ? basename(String(input["file_path"] ?? ""))
          : String(input["file_path"] ?? "");
      case "Glob":
        return format === "brief"
          ? String(input["pattern"] ?? "")
          : `glob:${String(input["pattern"] ?? "")}`;
      case "Grep":
        return format === "brief"
          ? String(input["pattern"] ?? "")
          : `grep:${String(input["pattern"] ?? "")}`;
      case "Agent":
        return format === "brief"
          ? String(input["description"] ?? "")
          : truncate(String(input["prompt"] ?? ""), 100);
      case "WebSearch":
        return format === "brief"
          ? String(input["query"] ?? "")
          : `search:${String(input["query"] ?? "")}`;
      case "WebFetch": {
        const url = String(input["url"] ?? "");
        return format === "brief" ? url.split("/").slice(-2).join("/") : url;
      }
      default:
        return "";
    }
  }

  private contextPressure(node: Node): boolean {
    const t = node.token;
    const total = t.inputTokens + t.cacheReadTokens + t.cacheCreationTokens;
    return total > CONTEXT_LIMIT * 0.7;
  }

  private sessionSummaryHtml(all: Node[]): string {
    const m = this.computeSessionMetrics(all);
    if (m.assistantNodes.length === 0) return "";
    const durationStr = this.computeDuration(all);

    const rows: string[] = [];
    rows.push(summaryStat("Prompts", String(m.allPrompts)));
    rows.push(summaryStat("Main turns", String(m.turns)));
    if (m.sub > 0) rows.push(summaryStat("Subagent turns", String(m.sub)));
    if (durationStr) rows.push(summaryStat("Duration", durationStr));
    if (m.models.length > 0) rows.push(summaryStat("Models", m.models));
    rows.push(summaryStat("Total cost", fmtCost(m.totalCost)));
    if (m.hitRate != null) rows.push(summaryStat("Cache hit rate", `${m.hitRate.toFixed(1)}%`));
    rows.push(summaryStat("Total input", `${fmt(m.totalInput)} tok`));
    rows.push(summaryStat("Total output", `${fmt(m.output)} tok`));
    if (m.compactions > 0) rows.push(summaryStat("Compaction events", String(m.compactions), true));
    if (m.pressure > 0) rows.push(summaryStat("High context turns", String(m.pressure), true));

    return `<div id="summary-panel" class="summary-panel" style="display:none">
  <div class="summary-panel-title">Session Summary <button class="summary-close" onclick="toggleSummary()">&#x2715;</button></div>
  <dl class="summary-dl">
    ${rows.join("\n    ")}
  </dl>
</div>`;
  }

  private costLabel(node: Node): string {
    return fmtCost(node.subtreeCost ?? 0);
  }

  private compactionNode(node: Node): boolean {
    return (
      isHumanPrompt(node.token) &&
      humanText(node.token).startsWith("This session is being continued")
    );
  }

  private heatmapHtml(nodes: Node[]): string {
    // Merge each compaction node into the preceding group -- it's overhead from that prompt
    const groups: Node[][] = [];
    for (const node of nodes) {
      if (this.compactionNode(node) && groups.length > 0) {
        groups[groups.length - 1].push(node);
      } else {
        groups.push([node]);
      }
    }
    this.hmCount = groups.length;

    const groupTokens = groups.map((g) => g.reduce((s, n) => s + (n.subtreeTokens ?? 0), 0));
    const groupCosts = groups.map((g) => g.reduce((s, n) => s + (n.subtreeCost ?? 0), 0));
    const minTok = Math.min(...groupTokens);
    const maxTok = Math.max(...groupTokens);
    const minCost = Math.min(...groupCosts);
    const maxCost = Math.max(...groupCosts);

    const cells = groups
      .map((group, i) => {
        const primary = group[0];
        const combinedTokens = groupTokens[i];
        const combinedCost = groupCosts[i];
        const hasCompaction = group.length > 1;

        const colorCost = heatmapColor(combinedCost, minCost, maxCost);
        const colorToken = heatmapColorToken(combinedTokens, minTok, maxTok);

        // x/w spans all nodes in the group
        const last = group[group.length - 1];
        const ox = primary.x ?? 0;
        const ow = (last.x ?? 0) + (last.w ?? 0) - (primary.x ?? 0);
        const cx = primary.costX ?? 0;
        const cw = (last.costX ?? 0) + (last.costW ?? 0) - (primary.costX ?? 0);

        const num = this.threadNumbers.get(primary.token.uuid);
        const tokStr = fmt(combinedTokens);
        const costStr = combinedCost > 0 ? ` \u00b7 ${fmtCost(combinedCost)}` : "";
        const compactNote = hasCompaction ? " \u00b7 \u21ba compaction" : "";
        const base = num ? `Thread ${num}` : `Prompt ${i + 1}`;
        const tipText = escHtml(
          escapeJs(`${base} \u00b7 ${tokStr} tokens${costStr}${compactNote}`),
        );
        const tipPrompt = escHtml(escapeJs(humanText(primary.token)));
        const promptSearch = escHtml(truncate(humanText(primary.token), 300).toLowerCase());

        const badge = hasCompaction ? `<span class="hm-compact-badge">\u21ba</span>` : "";
        return `<div class="hm-cell" tabindex="0" data-idx="${i}" data-cost="${combinedCost}" data-tokens="${combinedTokens}" data-prompt="${promptSearch}" data-color-cost="${colorCost}" data-color-token="${colorToken}" data-ox="${ox}" data-ow="${ow}" data-cx="${cx}" data-cw="${cw}" data-tip="${tipText}" data-tip-prompt="${tipPrompt}" style="background-color:${colorToken}" onmouseover="hmTip(this)" onmouseout="tip('')" onclick="openPrompt(${i})"><span class="hm-idx">${i + 1}</span>${badge}</div>`;
      })
      .join("\n");

    return `<div id="heatmap" class="heatmap">
  <div class="hm-meta">
    <span class="hm-hint">Hover to preview &middot; Click to open flame graph</span>
  </div>
  <div class="hm-controls">
    <span class="hm-section-label">Prompts</span>
    <input type="text" id="hm-search" class="hm-search" placeholder="Search prompts\u2026" oninput="filterHeatmap(this.value)">
    <button class="hm-sort-btn" id="hm-sort-btn" onclick="sortHeatmap()">&#x21C5; Sort by tokens</button>
    <div class="hm-legend" id="hm-legend">
      <span class="hm-legend-label" id="hm-legend-lo">few tokens</span>
      <span class="hm-legend-ramp" id="hm-legend-ramp" data-token-grad="linear-gradient(to right, #073030, #00CED1)" data-cost-grad="linear-gradient(to right, #200510, #FF1493)" style="background:linear-gradient(to right, #073030, #00CED1)"></span>
      <span class="hm-legend-label" id="hm-legend-hi">many</span>
    </div>
  </div>
  <div class="hm-grid" id="hm-grid">
    ${cells}
  </div>
  <div class="hm-empty" id="hm-empty">Click a prompt cell to explore its flame graph</div>
</div>`;
  }

  private js(): string {
    const config = `var W = ${this.canvasWidth}, MIN_LBL_PX = ${MIN_LABEL_PX}, hmCount = ${this.hmCount};`;
    const jsContent = readAsset("html.js");
    return `${config}\n${jsContent}`;
  }
}

// ---------------------------------------------------------------------------
// Module-level utility functions
// ---------------------------------------------------------------------------

function escapeJs(str: string): string {
  return str
    .replace(/\\/g, "\\\\")
    .replace(/'/g, "\\'")
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r");
}

function heatmapColor(value: number, minVal: number, maxVal: number): string {
  let t = maxVal === minVal ? 0.5 : (value - minVal) / (maxVal - minVal);
  t = t ** 0.7;
  const r = clamp(Math.round(32 + (255 - 32) * t), 0, 255);
  const g = clamp(Math.round(5 + (20 - 5) * t), 0, 255);
  const b = clamp(Math.round(16 + (147 - 16) * t), 0, 255);
  return `#${hex(r)}${hex(g)}${hex(b)}`;
}

function heatmapColorToken(value: number, minVal: number, maxVal: number): string {
  let t = maxVal === minVal ? 0.5 : (value - minVal) / (maxVal - minVal);
  t = t ** 0.7;
  const r = clamp(Math.round(7 + (0 - 7) * t), 0, 255);
  const g = clamp(Math.round(48 + (206 - 48) * t), 0, 255);
  const b = clamp(Math.round(48 + (209 - 48) * t), 0, 255);
  return `#${hex(r)}${hex(g)}${hex(b)}`;
}

function clamp(value: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, value));
}

function hex(n: number): string {
  return n.toString(16).padStart(2, "0");
}

function modelShort(model: string | null | undefined): string {
  if (!model) return "sub";
  for (const family of ["haiku", "sonnet", "opus"]) {
    if (model.includes(family)) return family;
  }
  return "sub";
}

function fmt(n: number): string {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n);
}

function fmtCost(usd: number): string {
  if (usd === 0) return "$0";
  if (usd >= 1.0) return `$${usd.toFixed(2)}`;
  if (usd >= 0.01) return `$${usd.toFixed(3)}`;
  return `$${usd.toFixed(4)}`;
}

function fmtDuration(secs: number): string {
  if (secs < 60) return `${secs}s`;
  const mins = Math.floor(secs / 60);
  const rem = secs % 60;
  if (mins < 60) return `${mins}m ${rem}s`;
  return `${Math.floor(mins / 60)}h ${mins % 60}m`;
}

function truncate(str: string, len: number): string {
  return str.length > len ? `${str.slice(0, len)}\u2026` : str;
}

function summaryStat(label: string, value: string, warn = false): string {
  const valClass = warn ? "summary-val summary-warn" : "summary-val";
  return `<dt class="summary-dt">${escHtml(label)}</dt><dd class="${valClass}">${escHtml(value)}</dd>`;
}
