// W, MIN_LBL_PX, and hmCount are injected as globals by html.rb before this script runs.
(() => {
  var costMode = false,
    zoomedEl = null;
  var hmActiveIdx = -1,
    hmSorted = false;
  function bars() {
    return Array.from(document.querySelectorAll(".bar:not(.total-bar)"));
  }
  function applyBar(el, nx, nw) {
    if (nx + nw <= 0 || nx >= W) {
      el.style.display = "none";
    } else {
      el.style.display = "";
      el.style.left = `${(nx / W) * 100}%`;
      el.style.width = `calc(${(Math.max(nw, 1) / W) * 100}% + 1px)`;
      const lbl = el.querySelector(".lbl");
      if (lbl) {
        if (nw < MIN_LBL_PX) {
          lbl.style.display = "none";
        } else {
          lbl.style.display = "";
          // Pin label to visible left edge when bar extends off-screen to the left
          lbl.style.paddingLeft = nx < 0 ? `calc(${(-nx / nw) * 100}% + 5px)` : "";
        }
      }
    }
  }
  function resetBtn() {
    return document.getElementById("reset-btn");
  }
  function withoutTransition(fn) {
    document.querySelectorAll(".bar").forEach((b) => {
      b.style.transition = "none";
    });
    fn();
    var first = document.querySelector(".bar");
    if (first) first.offsetHeight;
    document.querySelectorAll(".bar").forEach((b) => {
      b.style.transition = "";
    });
  }
  window.toggleTheme = () => {
    var root = document.documentElement;
    var isLight = root.getAttribute("data-theme") === "light";
    root.setAttribute("data-theme", isLight ? "dark" : "light");
    var btn = document.getElementById("theme-btn");
    if (btn) btn.textContent = isLight ? "\u25D0 Light" : "\u25D1 Dark";
  };
  window.toggleSummary = () => {
    var p = document.getElementById("summary-panel");
    var btn = document.getElementById("summary-btn");
    if (!p) return;
    var shown = p.style.display !== "none";
    p.style.display = shown ? "none" : "block";
    if (btn) btn.classList.toggle("active", !shown);
  };
  window.toggleCostView = () => {
    var wasZoomed = zoomedEl;
    if (wasZoomed) unzoom();
    costMode = !costMode;
    withoutTransition(() => {
      bars().forEach((b) => {
        var nx = costMode ? +b.getAttribute("data-cx") : +b.getAttribute("data-ox");
        var nw = costMode ? +b.getAttribute("data-cw") : +b.getAttribute("data-ow");
        applyBar(b, nx, nw);
        var lbl = b.querySelector(".lbl");
        if (lbl) {
          const text = b.getAttribute(costMode ? "data-cost-lbl" : "data-token-lbl");
          if (text !== null) lbl.textContent = text;
        }
      });
    });
    var tl = document.getElementById("total-lbl");
    if (tl) tl.innerHTML = tl.getAttribute(costMode ? "data-cost-text" : "data-token-text");
    var cb = document.getElementById("cost-btn");
    if (cb) {
      cb.textContent = costMode ? "# Token view" : "$ Cost view";
      cb.classList.toggle("active", costMode);
    }
    hmCells().forEach((c) => {
      c.style.backgroundColor = c.getAttribute(costMode ? "data-color-cost" : "data-color-token");
    });
    var sb = document.getElementById("hm-sort-btn");
    if (sb) sb.innerHTML = costMode ? "&#x21C5; Sort by cost" : "&#x21C5; Sort by tokens";
    var ramp = document.getElementById("hm-legend-ramp");
    if (ramp)
      ramp.style.background = costMode
        ? ramp.getAttribute("data-cost-grad")
        : ramp.getAttribute("data-token-grad");
    var lmLo = document.getElementById("hm-legend-lo");
    var lmHi = document.getElementById("hm-legend-hi");
    if (lmLo) lmLo.textContent = costMode ? "cheap" : "few tokens";
    if (lmHi) lmHi.textContent = costMode ? "costly" : "many";
    scaleHeatmap();
    if (hmSorted) {
      hmSorted = false; // reset so sortHeatmap() will re-sort
      sortHeatmap();
    }
    if (wasZoomed) {
      if (wasZoomed.classList?.contains("hm-cell")) {
        // ox/ow were stamped by zoomToRoot() inside unzoom() using the old costMode.
        // Clear them so openPrompt → zoomToRoot re-computes with the new costMode.
        bars().forEach((b) => {
          b.removeAttribute("ox");
          b.removeAttribute("ow");
        });
        openPrompt(+wasZoomed.getAttribute("data-idx"));
      } else if (hmActiveIdx >= 0) {
        // ox/ow were set by zoomToRoot() inside unzoom() using the old costMode.
        // Clear them so zoomToRoot + zoom below re-compute with the new costMode.
        bars().forEach((b) => {
          b.removeAttribute("ox");
          b.removeAttribute("ow");
        });
        const rootCell = document.querySelector(`.hm-cell[data-idx="${hmActiveIdx}"]`);
        withoutTransition(() => {
          if (rootCell) zoomToRoot(rootCell);
          zoom(wasZoomed);
        });
      } else {
        zoom(wasZoomed);
      }
    }
  };
  window.zoom = (el) => {
    var fx = costMode ? +el.getAttribute("data-cx") : +el.getAttribute("data-ox");
    var fw = costMode ? +el.getAttribute("data-cw") : +el.getAttribute("data-ow");
    if (fw >= W - 1) {
      return;
    }
    var wrap = document.getElementById("flame-wrap");
    var flame = document.querySelector(".flame");
    if (!flame.getAttribute("data-orig-w")) flame.setAttribute("data-orig-w", flame.style.width);
    flame.style.width = `${wrap.clientWidth}px`;
    wrap.scrollLeft = 0;
    bars().forEach((b) => {
      if (!b.getAttribute("ox")) {
        b.setAttribute("ox", costMode ? +b.getAttribute("data-cx") : +b.getAttribute("data-ox"));
        b.setAttribute("ow", costMode ? +b.getAttribute("data-cw") : +b.getAttribute("data-ow"));
      }
      applyBar(b, ((+b.getAttribute("ox") - fx) / fw) * W, (+b.getAttribute("ow") / fw) * W);
    });
    var btn = resetBtn();
    if (btn) btn.style.display = "inline-block";
    zoomedEl = el;
  };
  window.unzoom = () => {
    var flame = document.querySelector(".flame");
    var origW = flame.getAttribute("data-orig-w");
    if (origW) {
      flame.style.width = origW;
      flame.removeAttribute("data-orig-w");
    }
    bars().forEach((b) => {
      var ox = b.getAttribute("ox");
      if (ox) {
        applyBar(b, +ox, +b.getAttribute("ow"));
        b.removeAttribute("ox");
        b.removeAttribute("ow");
      }
    });
    var btn = resetBtn();
    if (btn) btn.style.display = "none";
    zoomedEl = null;
    // If we're still viewing a specific prompt, re-zoom to its root
    if (hmActiveIdx >= 0) {
      const hmCell = document.querySelector(`.hm-cell[data-idx="${hmActiveIdx}"]`);
      if (hmCell) zoomToRoot(hmCell);
    }
  };
  // resetZoom: if sub-zoomed inside a prompt → unzoom back to prompt view;
  // if viewing a prompt (or full overview) → close back to heatmap
  window.resetZoom = () => {
    if (zoomedEl?.classList && !zoomedEl.classList.contains("hm-cell")) {
      unzoom();
    } else {
      closePrompt();
    }
  };
  function esc(t) {
    return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  window.tip = (s, prompt) => {
    var el = document.getElementById("tip");
    if (!el) return;
    if (!s && !prompt) {
      el.innerHTML = '<span class="tip-label">Hover for details \u00b7 Click to zoom</span>';
      return;
    }
    var sep = '<span class="tip-sep">\u00b7</span>';
    var parts = s ? s.split(" | ").filter(Boolean) : [];
    var html = parts
      .map((p, i) => {
        var e = esc(p);
        if (p.charAt(0) === "\u26a0") return `<span class="tip-warn">${e}</span>`;
        if (i === 0 && p.indexOf("tokens") !== -1) return `<span class="tip-tokens">${e}</span>`;
        if (p.indexOf("claude-") !== -1 || /^(haiku|sonnet|opus)/.test(p))
          return `<span class="tip-model">${e}</span>`;
        if (/^[^:]*:\s/.test(p)) return `<span class="tip-label">${e}</span>`;
        return `<span class="tip-code">${e}</span>`;
      })
      .join(sep);
    if (prompt) html += `${html ? sep : ""}<span class="tip-prompt">${esc(prompt)}</span>`;
    el.innerHTML = html;
  };
  var mx = 0,
    my = 0;
  document.addEventListener("mousemove", (e) => {
    mx = e.clientX;
    my = e.clientY;
    var ft = document.getElementById("ftip");
    if (ft && ft.style.display !== "none") {
      ft.style.left = `${mx + 14}px`;
      ft.style.top = `${my - 38}px`;
    }
  });
  document.addEventListener("mouseover", (e) => {
    var bar = e.target.closest?.(".bar:not(.total-bar)");
    var ft = document.getElementById("ftip");
    if (!ft) return;
    if (bar) {
      const d = bar.getAttribute("data-ftip");
      if (d) {
        ft.textContent = d;
        ft.style.display = "block";
        ft.style.left = `${mx + 14}px`;
        ft.style.top = `${my - 38}px`;
      }
    }
  });
  document.addEventListener("mouseout", (e) => {
    var bar = e.target.closest?.(".bar:not(.total-bar)");
    if (bar) {
      const ft = document.getElementById("ftip");
      if (ft) ft.style.display = "none";
    }
  });
  // Disable transitions on initial load
  document.querySelectorAll(".bar").forEach((b) => {
    b.style.transition = "none";
  });
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      document.querySelectorAll(".bar").forEach((b) => {
        b.style.transition = "";
      });
    });
  });
  // Heatmap
  function hmCells() {
    return Array.from(document.querySelectorAll(".hm-cell"));
  }
  window.hmTip = (el) => {
    tip(el.getAttribute("data-tip"), el.getAttribute("data-tip-prompt"));
  };
  function zoomToRoot(cell) {
    var fx = costMode ? +cell.getAttribute("data-cx") : +cell.getAttribute("data-ox");
    var fw = costMode ? +cell.getAttribute("data-cw") : +cell.getAttribute("data-ow");
    if (fw <= 0) return;
    var wrap = document.getElementById("flame-wrap");
    var flame = document.querySelector(".flame");
    if (!flame.getAttribute("data-orig-w")) flame.setAttribute("data-orig-w", flame.style.width);
    flame.style.width = `${wrap.clientWidth}px`;
    wrap.scrollLeft = 0;
    bars().forEach((b) => {
      if (!b.getAttribute("ox")) {
        b.setAttribute("ox", costMode ? +b.getAttribute("data-cx") : +b.getAttribute("data-ox"));
        b.setAttribute("ow", costMode ? +b.getAttribute("data-cw") : +b.getAttribute("data-ow"));
      }
      applyBar(b, ((+b.getAttribute("ox") - fx) / fw) * W, (+b.getAttribute("ow") / fw) * W);
    });
    zoomedEl = cell;
  }
  window.openPrompt = (idx) => {
    hmActiveIdx = idx;
    var hm = document.getElementById("heatmap");
    if (hm) hm.classList.add("hm-strip");
    hmCells().forEach((c) => {
      c.classList.toggle("hm-active", +c.getAttribute("data-idx") === idx);
    });
    var fw = document.getElementById("flame-wrap");
    if (fw) fw.style.display = "";
    var back = document.getElementById("hm-back");
    if (back) back.style.display = "";
    var cell = document.querySelector(`.hm-cell[data-idx="${idx}"]`);
    if (cell) {
      withoutTransition(() => {
        zoomToRoot(cell);
      });
    }
    var btn = resetBtn();
    if (btn) btn.style.display = "none";
  };
  window.closePrompt = () => {
    hmActiveIdx = -1;
    unzoom();
    var fw = document.getElementById("flame-wrap");
    if (fw) fw.style.display = "none";
    var hm = document.getElementById("heatmap");
    if (hm) hm.classList.remove("hm-strip");
    hmCells().forEach((c) => {
      c.classList.remove("hm-active");
    });
    var back = document.getElementById("hm-back");
    if (back) back.style.display = "none";
  };
  window.sortHeatmap = () => {
    hmSorted = !hmSorted;
    var grid = document.getElementById("hm-grid");
    if (!grid) return;
    var cells = hmCells();
    if (hmSorted) {
      cells.sort((a, b) => {
        var av = costMode
          ? parseFloat(a.getAttribute("data-cost"))
          : parseInt(a.getAttribute("data-tokens"), 10);
        var bv = costMode
          ? parseFloat(b.getAttribute("data-cost"))
          : parseInt(b.getAttribute("data-tokens"), 10);
        return bv - av;
      });
    } else {
      cells.sort(
        (a, b) =>
          parseInt(a.getAttribute("data-idx"), 10) - parseInt(b.getAttribute("data-idx"), 10),
      );
    }
    cells.forEach((c) => {
      grid.appendChild(c);
    });
    scaleHeatmap();
    var btn = document.getElementById("hm-sort-btn");
    if (btn) btn.classList.toggle("active", hmSorted);
  };
  window.filterHeatmap = (query) => {
    var q = query.toLowerCase().trim();
    hmCells().forEach((c) => {
      var match = !q || (c.getAttribute("data-prompt") || "").indexOf(q) !== -1;
      c.classList.toggle("hm-dimmed", !match);
    });
    scaleHeatmap();
  };
  function scaleHeatmap() {
    var hm = document.getElementById("heatmap");
    if (hm?.classList.contains("hm-strip")) return;
    var allCells = hmCells();
    var cells = allCells.filter((c) => !c.classList.contains("hm-dimmed"));
    var n = cells.length || 1;
    var maxCell = Math.min(96, Math.max(36, Math.floor(1400 / Math.sqrt(n))));
    var minCell = 16;
    var vals = cells.map((c) =>
      costMode
        ? parseFloat(c.getAttribute("data-cost"))
        : parseInt(c.getAttribute("data-tokens"), 10),
    );
    var maxVal = Math.max.apply(null, vals) || 1;
    cells.forEach((c, i) => {
      var t = Math.sqrt(vals[i] / maxVal);
      var sz = Math.round(minCell + (maxCell - minCell) * t);
      c.style.width = `${sz}px`;
      c.style.height = `${sz}px`;
      var lbl = c.querySelector(".hm-idx");
      if (lbl) lbl.style.display = sz < 24 ? "none" : "";
    });
    allCells
      .filter((c) => c.classList.contains("hm-dimmed"))
      .forEach((c) => {
        c.style.width = `${minCell}px`;
        c.style.height = `${minCell}px`;
      });
  }
  document.addEventListener("keydown", (e) => {
    if (
      e.key === "Enter" &&
      document.activeElement &&
      document.activeElement.classList.contains("hm-cell")
    ) {
      e.preventDefault();
      openPrompt(+document.activeElement.getAttribute("data-idx"));
      return;
    }
    if (e.target && e.target.tagName === "INPUT") return;
    if (e.key === "c" && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      toggleCostView();
      return;
    }
    if (e.key === "t" && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      toggleTheme();
      return;
    }
    if (e.key === "s" && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      toggleSummary();
      return;
    }
    if (hmActiveIdx < 0) return;
    if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
      e.preventDefault();
      if (hmActiveIdx > 0) openPrompt(hmActiveIdx - 1);
    } else if (e.key === "ArrowRight" || e.key === "ArrowDown") {
      e.preventDefault();
      if (hmActiveIdx < hmCount - 1) openPrompt(hmActiveIdx + 1);
    } else if (e.key === "Escape") {
      e.preventDefault();
      closePrompt();
    }
  });
  scaleHeatmap();
})();
