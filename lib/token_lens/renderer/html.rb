# frozen_string_literal: true

require "time"

module TokenLens
  module Renderer
    class Html
      ROW_HEIGHT = 32
      COORD_WIDTH = 1200  # default logical coordinate space
      FONT_SIZE = 13
      MIN_LABEL_PX = 60  # hide label if bar is narrower than 60px

      def initialize(canvas_width: COORD_WIDTH)
        @canvas_width = canvas_width
      end

      LEGEND_ITEMS = [
        ["bar-c-human", "User prompt"],
        ["bar-c-task", "Task callback"],
        ["bar-c-assistant", "Assistant response"],
        ["bar-c-tool", "Tool call"],
        ["bar-c-sidechain", "Subagent turn"],
        ["bar-compaction", "Compaction"]
      ].freeze

      CONTEXT_LIMIT = 200_000  # all current Claude models

      def render(nodes)
        all_flat = flatten(nodes)
        all = all_flat.reject { |n| n[:w] <= 1 }
        max_depth = all.map { |n| n[:depth] }.max || 0
        flame_height = (max_depth + 2) * ROW_HEIGHT  # +1 for TOTAL bar at bottom
        total_top = (max_depth + 1) * ROW_HEIGHT
        total_tokens = nodes.sum { |n| n[:subtree_tokens] }
        total_cost = nodes.sum { |n| n[:subtree_cost] }
        total_tip = escape_js(escape_html(total_summary(all_flat)))
        @reread_files = build_reread_map(all)
        @thread_count = nodes.length
        @thread_numbers = {}
        all.select { |n| n[:depth] == 0 }.each_with_index { |n, i| @thread_numbers[n[:token].uuid] = i + 1 }
        @agent_labels = {}
        all.each do |n|
          id = n[:token].agent_id
          next unless id && !@agent_labels.key?(id)
          @agent_labels[id] = "A#{@agent_labels.size + 1}"
        end
        assign_alternation(nodes)
        @hm_count = nodes.length  # overridden by heatmap_html after grouping
        token_total_lbl = "TOTAL &middot; #{fmt(total_tokens)} tokens"
        cost_total_lbl = "TOTAL &middot; #{fmt_cost(total_cost)}"

        <<~HTML
          <!DOCTYPE html>
          <html data-theme="dark">
          <head>
          <meta charset="utf-8">
          <title>Token Lens · Brickell Research</title>
          <style>
          @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,400;0,600;1,400&display=swap');
          #{css}
          </style>
          </head>
          <body>
          <div class="header">
            <div>
              <div class="summary">#{summary_text(all_flat)}</div>
              <div class="legend" id="legend" style="display:none">#{legend_html}</div>
            </div>
            <div class="header-btns">
              <button class="theme-btn" id="theme-btn" onclick="toggleTheme()">&#x25D0; Light</button>
              <button class="summary-btn" id="summary-btn" onclick="toggleSummary()">&#x2261; Summary</button>
              <button class="cost-btn" id="cost-btn" onclick="toggleCostView()">$ Cost view</button>
              <button class="reset-btn" id="reset-btn" onclick="resetZoom()">&#x21A9; Reset zoom</button>
              <button class="export-btn" onclick="exportSVG()">&#x2913; Export</button>
            </div>
          </div>
          #{heatmap_html(nodes)}
          <div id="hm-back" class="hm-back" style="display:none" onclick="closePrompt()">&#x2190; All prompts</div>
          <div class="flame-wrap" id="flame-wrap" style="display:none">
          <div class="flame" style="width:#{@canvas_width}px;height:#{flame_height}px">
          <div class="bar total-bar" style="left:0%;width:100%;top:#{total_top}px" data-ox="0" data-ow="#{@canvas_width}" data-cx="0" data-cw="#{@canvas_width}" onmouseover="tip('#{total_tip}')" onmouseout="tip('')" onclick="if(hmActiveIdx<0)unzoom()"><span class="lbl total-lbl" id="total-lbl" data-token-text="#{token_total_lbl}" data-cost-text="#{cost_total_lbl}">#{token_total_lbl}</span></div>
          #{all.map { |n| bar_html(n) }.join("\n")}
          </div>
          </div>
          <div id="ftip" class="floattip"></div>
          <div id="tip" class="tip"><span class="tip-label">Hover for details &middot; Click to zoom</span></div>
          #{session_summary_html(all_flat)}
          <script>
          #{js}
          </script>
          </body>
          </html>
        HTML
      end

      private

      def flatten(nodes)
        nodes.flat_map { |n| [n, *flatten(n[:children])] }
      end

      def pct(val)
        (val.to_f / @canvas_width * 100).round(4)
      end

      def bar_html(node)
        t = node[:token]
        lbl = escape_html(label(node))
        clbl = cost_label(node)
        tip = escape_html(tooltip(node))
        left = pct(node[:x])
        width = pct(node[:w])
        lbl_hidden = (node[:w] < MIN_LABEL_PX) ? " style=\"display:none\"" : ""
        extra_class = " #{color_class(node)}"
        extra_class += " bar-alt" if node[:alt]
        extra_class += " bar-reread" if reread_bar?(node)
        # is_compaction on assistant turns is for summary counting only; color is set via color_class on the user prompt
        extra_class += " bar-pressure" if !t.is_compaction && context_pressure?(node)
        ftip = escape_html(token_summary(node))
        mouseover = if t.is_task_notification?
          summary = t.task_notification_summary || "Task callback"
          "tip('#{escape_js(tip)}','#{escape_html(escape_js(summary))}')"
        elsif t.is_human_prompt?
          "tip('#{escape_js(tip)}','#{escape_html(escape_js(t.human_text))}')"
        else
          "tip('#{escape_js(tip)}')"
        end
        badge = reread_bar?(node) ? "<span class=\"warn-badge\">\u26a0</span>" : ""
        <<~HTML.chomp
          <div class="bar#{extra_class}" style="left:#{left}%;width:calc(#{width}% + 1px);top:#{node[:y]}px" data-ox="#{node[:x]}" data-ow="#{node[:w]}" data-cx="#{node[:cost_x]}" data-cw="#{node[:cost_w]}" data-token-lbl="#{lbl}" data-cost-lbl="#{clbl}" data-ftip="#{ftip}" onmouseover="#{mouseover}" onmouseout="tip('')" onclick="zoom(this)"><span class="lbl"#{lbl_hidden}>#{lbl}</span>#{badge}</div>
        HTML
      end

      def build_reread_map(all)
        counts = Hash.new(0)
        all.each do |node|
          node[:token].tool_uses.each do |tu|
            next unless %w[Read Write Edit].include?(tu["name"])
            path = tu.dig("input", "file_path").to_s
            counts[path] += 1 unless path.empty?
          end
        end
        counts.select { |_, v| v > 1 }
      end

      def token_summary(node)
        t = node[:token]
        tok = fmt(node[:subtree_tokens])
        cost = (node[:subtree_cost] > 0) ? " \u00b7 #{fmt_cost(node[:subtree_cost])}" : ""
        if t.is_task_notification?
          summary = t.task_notification_summary || "Task callback"
          name = summary.match(/Agent "([^"]+)"/)&.[](1) || summary
          "\u21a9 #{name} \u00b7 #{tok} tokens#{cost}"
        elsif t.is_human_prompt?
          num = @thread_numbers&.[](t.uuid)
          num ? "Thread #{num} \u00b7 #{tok} tokens#{cost}" : "#{tok} tokens#{cost}"
        elsif t.is_sidechain
          "[#{model_short(t.model)}] #{tok} tokens#{cost}"
        else
          "#{tok} tokens#{cost}"
        end
      end

      def reread_bar?(node)
        node[:token].tool_uses.any? do |tu|
          next unless %w[Read Write Edit].include?(tu["name"])
          path = tu.dig("input", "file_path").to_s
          @reread_files.key?(path)
        end
      end

      def tool_result_tokens(node)
        return 0 unless node[:token].tool_uses.any?
        user_child = node[:children].find { |c| c[:token].role == "user" && c[:token].tool_results.any? }
        return 0 unless user_child
        chars = node[:token].tool_uses.sum do |tu|
          tr = user_child[:token].tool_results.find { |r| r["tool_use_id"] == tu["id"] }
          next 0 unless tr
          Array(tr["content"]).sum { |c| c.is_a?(Hash) ? c.dig("text").to_s.length : c.to_s.length }
        end
        chars / 4
      end

      def compute_session_metrics(all)
        anodes = all.select { |n| n[:token].role == "assistant" }
        raw_input = anodes.sum { |n| n[:token].input_tokens }
        cached = anodes.sum { |n| n[:token].cache_read_tokens }
        cache_new = anodes.sum { |n| n[:token].cache_creation_tokens }
        total_input = raw_input + cached + cache_new
        {
          assistant_nodes: anodes,
          prompts: all.count { |n| n[:token].is_human_prompt? && !n[:token].is_task_notification? },
          all_prompts: all.count { |n| n[:token].is_human_prompt? },
          tasks: all.count { |n| n[:token].is_task_notification? },
          turns: anodes.count { |n| !n[:token].is_sidechain },
          sub: anodes.count { |n| n[:token].is_sidechain },
          marginal: anodes.sum { |n| n[:token].marginal_input_tokens },
          cached: cached,
          cache_new: cache_new,
          output: anodes.sum { |n| n[:token].output_tokens },
          total_cost: anodes.sum { |n| n[:token].cost_usd },
          total_input: total_input,
          hit_rate: (total_input > 0 && cached > 0) ? (cached.to_f / total_input * 100) : nil,
          compactions: all.count { |n| n[:token].is_human_prompt? && n[:token].human_text.start_with?("This session is being continued") },
          pressure: anodes.count { |n| context_pressure?(n) },
          models: anodes.map { |n| n[:token].model }.compact.map { |m| model_short(m) }.uniq.join(", ")
        }
      end

      def compute_duration(all)
        timestamps = all.map { |n| n[:token].timestamp }.compact.sort
        return nil unless timestamps.length >= 2
        secs = (Time.parse(timestamps.last) - Time.parse(timestamps.first)).to_i
        fmt_duration(secs) if secs > 0
      rescue
        nil
      end

      def summary_text(all)
        m = compute_session_metrics(all)
        parts = []
        parts << "#{@thread_count} threads" if @thread_count&.> 1
        parts << "#{m[:prompts]} #{"prompt".then { |w| (m[:prompts] == 1) ? w : "#{w}s" }}"
        parts << "#{m[:tasks]} #{"task callback".then { |w| (m[:tasks] == 1) ? w : "#{w}s" }}" if m[:tasks] > 0
        parts << "#{m[:turns]} main #{"turn".then { |w| (m[:turns] == 1) ? w : "#{w}s" }}"
        parts << "#{m[:sub]} subagent #{"turn".then { |w| (m[:sub] == 1) ? w : "#{w}s" }}" if m[:sub] > 0
        parts << compute_duration(all)
        parts << "fresh input: #{fmt(m[:marginal])}" if m[:marginal] > 0
        parts << "cached input: #{fmt(m[:cached])}" if m[:cached] > 0
        parts << "written to cache: #{fmt(m[:cache_new])}" if m[:cache_new] > 0
        parts << "cache hit: #{m[:hit_rate].round(0).to_i}%" if m[:hit_rate]
        parts << "output: #{fmt(m[:output])}" if m[:output] > 0
        parts << fmt_cost(m[:total_cost]) if m[:total_cost] > 0
        parts.compact.join(" &middot; ")
      end

      def total_summary(all)
        m = compute_session_metrics(all)
        parts = []
        parts << "fresh input: #{fmt(m[:marginal])}" if m[:marginal] > 0
        parts << "cached input: #{fmt(m[:cached])}" if m[:cached] > 0
        parts << "written to cache: #{fmt(m[:cache_new])}" if m[:cache_new] > 0
        parts << "output: #{fmt(m[:output])}" if m[:output] > 0
        parts << "cost: #{fmt_cost(m[:total_cost])}" if m[:total_cost] > 0
        parts.join(" | ")
      end

      def thread_separators(all)
        roots = all.select { |n| n[:depth] == 0 }
        return "" if roots.size <= 1
        # Emit a vertical line at the right edge of each thread (except the last)
        roots[0..-2].map { |n|
          right_x = n[:x] + n[:w]
          pct_val = pct(right_x)
          %(<div class="thread-sep" style="left:#{pct_val}%"></div>)
        }.join("\n")
      end

      def assign_alternation(siblings)
        siblings.each_with_index do |node, i|
          node[:alt] = i.odd?
          assign_alternation(node[:children])
        end
      end

      def legend_html
        LEGEND_ITEMS.map { |css_class, lbl|
          %(<span class="legend-item"><span class="legend-swatch #{css_class}"></span>#{lbl}</span>)
        }.join
      end

      def color_class(node)
        t = node[:token]
        return "bar-c-task" if t.is_task_notification?
        return "bar-c-sidechain" if t.is_sidechain
        return "bar-compaction" if t.is_human_prompt? && t.human_text.start_with?("This session is being continued")
        return "bar-c-human" if t.is_human_prompt?
        case t.role
        when "user" then "bar-c-user"
        when "assistant"
          t.tool_uses.any? ? "bar-c-tool" : "bar-c-assistant"
        else "bar-c-user"
        end
      end

      def label(node)
        t = node[:token]
        if t.is_task_notification?
          summary = t.task_notification_summary || "Task callback"
          name = summary.match(/Agent "([^"]+)"/)&.[](1) || summary
          "\u21a9 #{name}"
        elsif t.is_human_prompt?
          t.human_text
        elsif t.role == "assistant" && t.tool_uses.any?
          uses = t.tool_uses
          tool_str = if uses.length == 1
            brief = tool_input(uses.first, format: :brief)
            brief.empty? ? uses.first["name"] : "#{uses.first["name"]}: #{brief}"
          else
            uses.map { |u| u["name"] }.join(", ")
          end
          badge = t.is_sidechain && t.agent_id && @agent_labels&.[](t.agent_id)
          badge ? "[#{badge}] #{tool_str}" : tool_str
        elsif t.role == "assistant"
          if t.is_sidechain
            agent_lbl = t.agent_id && @agent_labels&.[](t.agent_id)
            prefix = agent_lbl ? "[#{model_short(t.model)} \u00b7 #{agent_lbl}] " : "[#{model_short(t.model)}] "
          else
            prefix = ""
          end
          text = t.content.find { |c| c.is_a?(Hash) && c["type"] == "text" }&.dig("text").to_s.strip
          (text.length > 0) ? "#{prefix}#{text}" : "#{prefix}response \u00b7 out: #{fmt(t.output_tokens)}"
        else
          t.role
        end
      end

      def tooltip(node)
        t = node[:token]
        parts = []
        if t.is_human_prompt?
          # tip bar shows only the prompt text (via 2nd arg); no redundant stats here
        else
          parts << "#{fmt(node[:subtree_tokens])} tokens"
          parts << t.model if t.model
          parts << "fresh input: #{fmt(t.marginal_input_tokens)}" if t.marginal_input_tokens > 0
          parts << "cached input: #{fmt(t.cache_read_tokens)}" if t.cache_read_tokens > 0
          parts << "written to cache: #{fmt(t.cache_creation_tokens)}" if t.cache_creation_tokens > 0
          parts << "output: #{fmt(t.output_tokens)}"
          parts << "cost: #{fmt_cost(t.cost_usd)}" if t.cost_usd > 0
          t.tool_uses.each { |tool| parts << tool_input(tool, format: :detail) unless tool_input(tool, format: :detail).empty? }
          result_tok = tool_result_tokens(node)
          parts << "result: ~#{fmt(result_tok)} tokens" if result_tok > 0
          parts << "subagent" if t.is_sidechain
          parts << "agent: #{t.agent_id}" if t.agent_id
          t.tool_uses.each do |tu|
            next unless %w[Read Write Edit].include?(tu["name"])
            path = tu.dig("input", "file_path").to_s
            count = @reread_files&.[](path)
            parts << "⚠ #{File.basename(path)} accessed #{count}x in session" if count
          end
        end
        parts.join(" | ")
      end

      def tool_input(tool, format:)
        input = tool["input"] || {}
        cmd = -> { (input["command"] || "").strip.sub(/\Asource[^\n&]+&&\s*rvm[^\n&]+&&\s*/, "") }
        case tool["name"]
        when "Bash"
          (format == :brief) ? cmd.call : truncate(cmd.call, 100)
        when "Read", "Write", "Edit"
          (format == :brief) ? File.basename(input["file_path"].to_s) : input["file_path"].to_s
        when "Glob"
          (format == :brief) ? input["pattern"].to_s : "glob:#{input["pattern"]}"
        when "Grep"
          (format == :brief) ? input["pattern"].to_s : "grep:#{input["pattern"]}"
        when "Agent"
          (format == :brief) ? input["description"].to_s : truncate(input["prompt"].to_s, 100)
        when "WebSearch"
          (format == :brief) ? input["query"].to_s : "search:#{input["query"]}"
        when "WebFetch"
          (format == :brief) ? input["url"].to_s.split("/").last(2).join("/") : input["url"].to_s
        else ""
        end
      end

      def model_short(model)
        return "sub" unless model
        %w[haiku sonnet opus].find { |f| model.include?(f) } || "sub"
      end

      def context_pressure?(node)
        t = node[:token]
        total = t.input_tokens + t.cache_read_tokens + t.cache_creation_tokens
        total > CONTEXT_LIMIT * 0.7
      end

      def session_summary_html(all)
        m = compute_session_metrics(all)
        return "" if m[:assistant_nodes].empty?
        duration_str = compute_duration(all)

        rows = []
        rows << summary_stat("Prompts", m[:all_prompts].to_s)
        rows << summary_stat("Main turns", m[:turns].to_s)
        rows << summary_stat("Subagent turns", m[:sub].to_s) if m[:sub] > 0
        rows << summary_stat("Duration", duration_str) if duration_str
        rows << summary_stat("Models", m[:models]) unless m[:models].empty?
        rows << summary_stat("Total cost", fmt_cost(m[:total_cost]))
        rows << summary_stat("Cache hit rate", "#{m[:hit_rate].round(1)}%") if m[:hit_rate]
        rows << summary_stat("Total input", "#{fmt(m[:total_input])} tok")
        rows << summary_stat("Total output", "#{fmt(m[:output])} tok")
        rows << summary_stat("Compaction events", m[:compactions].to_s, warn: true) if m[:compactions] > 0
        rows << summary_stat("High context turns", m[:pressure].to_s, warn: true) if m[:pressure] > 0

        <<~HTML
          <div id="summary-panel" class="summary-panel" style="display:none">
            <div class="summary-panel-title">Session Summary <button class="summary-close" onclick="toggleSummary()">&#x2715;</button></div>
            <dl class="summary-dl">
              #{rows.join("\n      ")}
            </dl>
          </div>
        HTML
      end

      def summary_stat(label, value, warn: false)
        val_class = warn ? "summary-val summary-warn" : "summary-val"
        "<dt class=\"summary-dt\">#{escape_html(label)}</dt><dd class=\"#{val_class}\">#{escape_html(value)}</dd>"
      end

      def fmt_duration(secs)
        return "#{secs}s" if secs < 60
        mins = secs / 60
        rem = secs % 60
        return "#{mins}m #{rem}s" if mins < 60
        "#{mins / 60}h #{mins % 60}m"
      end

      def cost_label(node)
        fmt_cost(node[:subtree_cost])
      end

      def fmt(n)
        (n >= 1000) ? "#{(n / 1000.0).round(1)}k" : n.to_s
      end

      def fmt_cost(usd)
        return "$0" if usd == 0
        if usd >= 1.0
          "$%.2f" % usd
        elsif usd >= 0.01
          "$%.3f" % usd
        else
          "$%.4f" % usd
        end
      end

      def truncate(str, len)
        (str.length > len) ? "#{str[0, len]}…" : str
      end

      def escape_html(str)
        str.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end

      def escape_js(str)
        str.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }.gsub("\n", "\\n").gsub("\r", "\\r")
      end

      def heatmap_color(value, min_val, max_val)
        t = (max_val == min_val) ? 0.5 : ((value - min_val).to_f / (max_val - min_val))
        t **= 0.7
        r = (32 + (255 - 32) * t).round.clamp(0, 255)
        g = (5 + (20 - 5) * t).round.clamp(0, 255)
        b = (16 + (147 - 16) * t).round.clamp(0, 255)
        "#%02x%02x%02x" % [r, g, b]
      end

      def heatmap_color_token(value, min_val, max_val)
        t = (max_val == min_val) ? 0.5 : ((value - min_val).to_f / (max_val - min_val))
        t **= 0.7
        r = (7 + (0 - 7) * t).round.clamp(0, 255)
        g = (48 + (206 - 48) * t).round.clamp(0, 255)
        b = (48 + (209 - 48) * t).round.clamp(0, 255)
        "#%02x%02x%02x" % [r, g, b]
      end

      def compaction_node?(node)
        node[:token].is_human_prompt? && node[:token].human_text.start_with?("This session is being continued")
      end

      def heatmap_html(nodes)
        # Merge each compaction node into the preceding group — it's overhead from that prompt
        groups = []
        nodes.each do |node|
          if compaction_node?(node) && groups.any?
            groups.last << node
          else
            groups << [node]
          end
        end
        @hm_count = groups.length

        group_tokens = groups.map { |g| g.sum { |n| n[:subtree_tokens] } }
        group_costs = groups.map { |g| g.sum { |n| n[:subtree_cost] } }
        min_tok, max_tok = group_tokens.min, group_tokens.max
        min_cost, max_cost = group_costs.min, group_costs.max

        cells = groups.each_with_index.map { |group, i|
          primary = group.first
          combined_tokens = group_tokens[i]
          combined_cost = group_costs[i]
          has_compaction = group.length > 1

          color_cost = heatmap_color(combined_cost, min_cost, max_cost)
          color_token = heatmap_color_token(combined_tokens, min_tok, max_tok)

          # x/w spans all nodes in the group
          ox = primary[:x]
          ow = group.last[:x] + group.last[:w] - primary[:x]
          cx = primary[:cost_x]
          cw = group.last[:cost_x] + group.last[:cost_w] - primary[:cost_x]

          num = @thread_numbers&.[](primary[:token].uuid)
          tok_str = fmt(combined_tokens)
          cost_str = (combined_cost > 0) ? " \u00b7 #{fmt_cost(combined_cost)}" : ""
          compact_note = has_compaction ? " \u00b7 \u21ba compaction" : ""
          base = num ? "Thread #{num}" : "Prompt #{i + 1}"
          tip_text = escape_html(escape_js("#{base} \u00b7 #{tok_str} tokens#{cost_str}#{compact_note}"))
          tip_prompt = escape_html(escape_js(primary[:token].human_text))
          prompt_search = escape_html(truncate(primary[:token].human_text, 300).downcase)

          badge = has_compaction ? %(<span class="hm-compact-badge">\u21ba</span>) : ""
          %(<div class="hm-cell" tabindex="0" data-idx="#{i}" data-cost="#{combined_cost}" data-tokens="#{combined_tokens}" data-prompt="#{prompt_search}" data-color-cost="#{color_cost}" data-color-token="#{color_token}" data-ox="#{ox}" data-ow="#{ow}" data-cx="#{cx}" data-cw="#{cw}" data-tip="#{tip_text}" data-tip-prompt="#{tip_prompt}" style="background-color:#{color_token}" onmouseover="hmTip(this)" onmouseout="tip('')" onclick="openPrompt(#{i})"><span class="hm-idx">#{i + 1}</span>#{badge}</div>)
        }.join("\n")

        <<~HTML
          <div id="heatmap" class="heatmap">
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
              #{cells}
            </div>
            <div class="hm-empty" id="hm-empty">Click a prompt cell to explore its flame graph</div>
          </div>
        HTML
      end

      def css
        File.read(File.join(__dir__, "html.css"))
      end

      def js
        config = "var W = #{@canvas_width}, MIN_LBL_PX = #{MIN_LABEL_PX}, hmCount = #{@hm_count};"
        "#{config}\n#{File.read(File.join(__dir__, "html.js"))}"
      end
    end
  end
end
