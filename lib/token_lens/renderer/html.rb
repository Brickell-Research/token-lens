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

      def summary_text(all)
        assistant_nodes = all.select { |n| n[:token].role == "assistant" }
        prompts = all.count { |n| n[:token].is_human_prompt? && !n[:token].is_task_notification? }
        tasks = all.count { |n| n[:token].is_task_notification? }
        turns = assistant_nodes.count { |n| !n[:token].is_sidechain }
        sub = assistant_nodes.count { |n| n[:token].is_sidechain }
        marginal = assistant_nodes.sum { |n| n[:token].marginal_input_tokens }
        cached = assistant_nodes.sum { |n| n[:token].cache_read_tokens }
        cache_new = assistant_nodes.sum { |n| n[:token].cache_creation_tokens }
        raw_input = assistant_nodes.sum { |n| n[:token].input_tokens }
        output = assistant_nodes.sum { |n| n[:token].output_tokens }
        total_cost = assistant_nodes.sum { |n| n[:token].cost_usd }
        total_input = raw_input + cached + cache_new
        hit_rate = (total_input > 0 && cached > 0) ? (cached.to_f / total_input * 100).round(0).to_i : nil
        parts = []
        timestamps = all.map { |n| n[:token].timestamp }.compact.sort
        duration = begin
          secs = (Time.parse(timestamps.last) - Time.parse(timestamps.first)).to_i
          fmt_duration(secs) if timestamps.length >= 2 && secs > 0
        rescue
          nil
        end
        parts << "#{@thread_count} threads" if @thread_count&.> 1
        parts << "#{prompts} #{"prompt".then { |w| (prompts == 1) ? w : "#{w}s" }}"
        parts << "#{tasks} #{"task callback".then { |w| (tasks == 1) ? w : "#{w}s" }}" if tasks > 0
        parts << "#{turns} main #{"turn".then { |w| (turns == 1) ? w : "#{w}s" }}"
        parts << "#{sub} subagent #{"turn".then { |w| (sub == 1) ? w : "#{w}s" }}" if sub > 0
        parts << duration if duration
        parts << "fresh input: #{fmt(marginal)}" if marginal > 0
        parts << "cached input: #{fmt(cached)}" if cached > 0
        parts << "written to cache: #{fmt(cache_new)}" if cache_new > 0
        parts << "cache hit: #{hit_rate}%" if hit_rate
        parts << "output: #{fmt(output)}" if output > 0
        parts << fmt_cost(total_cost) if total_cost > 0
        parts.join(" &middot; ")
      end

      def total_summary(all)
        assistant_nodes = all.select { |n| n[:token].role == "assistant" }
        marginal = assistant_nodes.sum { |n| n[:token].marginal_input_tokens }
        cached = assistant_nodes.sum { |n| n[:token].cache_read_tokens }
        cache_new = assistant_nodes.sum { |n| n[:token].cache_creation_tokens }
        output = assistant_nodes.sum { |n| n[:token].output_tokens }
        total_cost = assistant_nodes.sum { |n| n[:token].cost_usd }
        parts = []
        parts << "fresh input: #{fmt(marginal)}" if marginal > 0
        parts << "cached input: #{fmt(cached)}" if cached > 0
        parts << "written to cache: #{fmt(cache_new)}" if cache_new > 0
        parts << "output: #{fmt(output)}" if output > 0
        parts << "cost: #{fmt_cost(total_cost)}" if total_cost > 0
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
            brief = tool_brief(uses.first)
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
          t.tool_uses.each { |tool| parts << tool_detail(tool) unless tool_detail(tool).empty? }
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

      def tool_brief(tool)
        input = tool["input"] || {}
        case tool["name"]
        when "Bash"
          (input["command"] || "").strip.sub(/\Asource[^\n&]+&&\s*rvm[^\n&]+&&\s*/, "")
        when "Read", "Write", "Edit"
          File.basename(input["file_path"].to_s)
        when "Glob" then input["pattern"].to_s
        when "Grep" then input["pattern"].to_s
        when "Agent" then input["description"].to_s
        when "WebSearch" then input["query"].to_s
        when "WebFetch" then input["url"].to_s.split("/").last(2).join("/")
        else ""
        end
      end

      def tool_detail(tool)
        input = tool["input"] || {}
        case tool["name"]
        when "Bash"
          cmd = (input["command"] || "").strip.sub(/\Asource[^\n&]+&&\s*rvm[^\n&]+&&\s*/, "")
          truncate(cmd, 100)
        when "Read", "Write", "Edit" then input["file_path"].to_s
        when "Glob" then "glob:#{input["pattern"]}"
        when "Grep" then "grep:#{input["pattern"]}"
        when "Agent" then truncate(input["prompt"].to_s, 100)
        when "WebSearch" then "search:#{input["query"]}"
        when "WebFetch" then input["url"].to_s
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
        assistant_nodes = all.select { |n| n[:token].role == "assistant" }
        return "" if assistant_nodes.empty?

        prompts = all.count { |n| n[:token].is_human_prompt? }
        turns = assistant_nodes.count { |n| !n[:token].is_sidechain }
        sub = assistant_nodes.count { |n| n[:token].is_sidechain }
        raw_input = assistant_nodes.sum { |n| n[:token].input_tokens }
        cached = assistant_nodes.sum { |n| n[:token].cache_read_tokens }
        cache_new = assistant_nodes.sum { |n| n[:token].cache_creation_tokens }
        output = assistant_nodes.sum { |n| n[:token].output_tokens }
        total_input = raw_input + cached + cache_new
        hit_rate = (total_input > 0 && cached > 0) ? (cached.to_f / total_input * 100).round(1) : nil
        total_cost = assistant_nodes.sum { |n| n[:token].cost_usd }
        compactions = all.count { |n| n[:token].is_human_prompt? && n[:token].human_text.start_with?("This session is being continued") }
        pressure = assistant_nodes.count { |n| context_pressure?(n) }
        models = assistant_nodes.map { |n| n[:token].model }.compact
          .map { |m| model_short(m) }.uniq.join(", ")

        timestamps = all.map { |n| n[:token].timestamp }.compact.sort
        duration_str = if timestamps.length >= 2
          begin
            secs = (Time.parse(timestamps.last) - Time.parse(timestamps.first)).to_i
            fmt_duration(secs)
          rescue
            nil
          end
        end

        rows = []
        rows << summary_stat("Prompts", prompts.to_s)
        rows << summary_stat("Main turns", turns.to_s)
        rows << summary_stat("Subagent turns", sub.to_s) if sub > 0
        rows << summary_stat("Duration", duration_str) if duration_str
        rows << summary_stat("Models", models) unless models.empty?
        rows << summary_stat("Total cost", fmt_cost(total_cost))
        rows << summary_stat("Cache hit rate", "#{hit_rate}%") if hit_rate
        rows << summary_stat("Total input", "#{fmt(total_input)} tok")
        rows << summary_stat("Total output", "#{fmt(output)} tok")
        rows << summary_stat("Compaction events", compactions.to_s, warn: true) if compactions > 0
        rows << summary_stat("High context turns", pressure.to_s, warn: true) if pressure > 0

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
        <<~CSS
          :root {
            --bar-human: #FF1493;
            --bar-task: #FFB020;
            --bar-assistant: #00CED1;
            --bar-tool: #00A8E8;
            --bar-sidechain: #C97BFF;
            --bar-compaction: #607B8B;
            --bar-user: #1a1a2e;
            --bg: #000000;
            --surface: #0a0a14;
            --border: #1a1a2e;
            --text: #c8d4dc;
            --text-dim: #8892a0;
            --bar-text: #000000;
            --bar-border: #000000;
            --shadow: rgba(0,0,0,0.8);
            --accent: #FF1493;
            --accent2: #00CED1;
            --accent-faint: rgba(255,20,147,0.6);
          }
          :root[data-theme="light"] {
            --bar-user: #c8ccd8;
            --bg: #f8f8fc;
            --surface: #ffffff;
            --border: #d8dae8;
            --text: #1a1a2e;
            --text-dim: #5a6070;
            --bar-border: #e0e0ec;
            --shadow: rgba(0,0,0,0.12);
            --accent-faint: rgba(255,20,147,0.45);
          }
          * { box-sizing: border-box; margin: 0; padding: 0; }
          html, body { height: 100%; }
          body { background: var(--bg); font-family: 'JetBrains Mono', 'Cascadia Mono', 'Fira Code', ui-monospace, monospace; font-size: #{FONT_SIZE}px; display: flex; flex-direction: column; height: 100%; color: var(--text); }
          .header { display: flex; align-items: center; justify-content: space-between; padding: 4px 8px; border-bottom: 1px solid var(--border); }
          .summary { color: var(--text-dim); font-size: 11px; line-height: 20px; }
          .header-btns { display: flex; gap: 6px; align-items: center; }
          .cost-btn { background: none; border: 1px solid var(--border); color: var(--text-dim); border-radius: 3px; padding: 2px 8px; font-size: 10px; cursor: pointer; font-family: inherit; }
          .cost-btn:hover { background: var(--surface); color: var(--text); border-color: var(--accent2); }
          .cost-btn.active { border-color: var(--accent2); color: var(--accent2); }
          .reset-btn { background: none; border: 1px solid var(--border); color: var(--text-dim); border-radius: 3px; padding: 2px 8px; font-size: 10px; cursor: pointer; display: none; font-family: inherit; }
          .reset-btn:hover { background: var(--surface); color: var(--text); border-color: var(--accent); }
          .theme-btn { background: none; border: 1px solid var(--border); color: var(--text-dim); border-radius: 3px; padding: 2px 8px; font-size: 10px; cursor: pointer; font-family: inherit; }
          .theme-btn:hover { background: var(--surface); color: var(--text); border-color: var(--accent2); }
          .flame-wrap { flex: 1; display: flex; flex-direction: column; justify-content: flex-end; overflow-x: auto; overflow-y: hidden; width: 100%; }
          .flame { position: relative; overflow: hidden; flex-shrink: 0; }
          .heatmap { flex-shrink: 0; padding: 12px 8px 8px; background: var(--bg); border-bottom: 1px solid var(--border); }
          .hm-meta { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
          .hm-controls { display: flex; gap: 8px; align-items: center; justify-content: center; margin-bottom: 8px; }
          .hm-search { background: var(--surface); border: 1px solid var(--border); color: var(--text); border-radius: 3px; padding: 3px 8px; font-size: 11px; font-family: inherit; outline: none; width: 220px; }
          .hm-search:focus { border-color: var(--accent2); }
          .hm-sort-btn { background: none; border: 1px solid var(--border); color: var(--text-dim); border-radius: 3px; padding: 2px 8px; font-size: 10px; cursor: pointer; font-family: inherit; }
          .hm-sort-btn:hover { background: var(--surface); color: var(--text); border-color: var(--accent2); }
          .hm-sort-btn.active { border-color: var(--accent2); color: var(--accent2); }
          .hm-grid { display: flex; flex-wrap: wrap; gap: 3px; justify-content: center; }
          .hm-cell { width: 32px; height: 32px; border-radius: 3px; cursor: pointer; transition: opacity 0.1s ease-out, transform 0.1s ease-out, box-shadow 0.1s ease-out; flex-shrink: 0; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center; position: relative; }
          .hm-cell:hover { transform: scale(1.08); z-index: 10; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.10), 0 0 8px var(--accent-faint); }
          .hm-cell:focus-visible { outline: 2px solid var(--accent2); outline-offset: 1px; z-index: 10; }
          .hm-cell.hm-active { box-shadow: 0 0 0 2px var(--accent); transform: scale(1.15); z-index: 11; }
          .hm-idx { font-size: 9px; font-weight: 700; color: rgba(255,255,255,0.6); pointer-events: none; line-height: 1; user-select: none; }
          .hm-compact-badge { position: absolute; top: 2px; right: 3px; font-size: 8px; color: rgba(255,255,255,0.75); pointer-events: none; line-height: 1; }
          .hm-cell.hm-dimmed { opacity: 0.15; }
          .heatmap.hm-strip { padding: 4px 8px; border-bottom: 1px solid var(--border); }
          .heatmap.hm-strip .hm-meta { display: none; }
          .heatmap.hm-strip .hm-controls { display: none; }
          .heatmap.hm-strip .hm-grid { gap: 2px; }
          .heatmap.hm-strip .hm-cell { width: 16px; height: 16px; border-radius: 2px; }
          .hm-back { padding: 4px 12px; font-size: 11px; color: var(--accent); cursor: pointer; border-bottom: 1px solid var(--border); background: var(--surface); user-select: none; }
          .hm-back:hover { background: var(--border); }
          .heatmap.hm-strip .hm-idx { display: none; }
          .hm-section-label { color: var(--text-dim); font-size: 10px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; white-space: nowrap; }
          .hm-hint { color: var(--text-dim); font-size: 10px; opacity: 0.6; white-space: nowrap; }
          .hm-legend { display: flex; align-items: center; gap: 4px; }
          .hm-legend-label { color: var(--text-dim); font-size: 9px; opacity: 0.7; white-space: nowrap; }
          .hm-legend-ramp { width: 64px; height: 8px; border-radius: 2px; flex-shrink: 0; }
          .hm-empty { color: var(--text-dim); font-size: 12px; text-align: center; padding: 40px 0 20px; opacity: 0.5; }
          .heatmap.hm-strip .hm-empty { display: none; }
          .bar {
            position: absolute;
            height: #{ROW_HEIGHT}px;
            border-radius: 0;
            border-right: 1.5px solid rgba(0,0,0,0.5);
            box-shadow: inset 0 1px 0 rgba(255,255,255,0.10), inset 0 -1px 0 rgba(0,0,0,0.25);
            cursor: pointer;
            overflow: hidden;
            user-select: none;
            transition: left 0.2s ease, width 0.2s ease;
          }
          .bar:hover { filter: brightness(1.18) saturate(1.1); }
          .bar-reread { box-shadow: inset 0 -2px 0 var(--accent); }
          .bar-compaction { background: linear-gradient(to right, #7a96a8 0%, #607B8B 12%, #607B8B 88%, #4a6070 100%) !important; box-shadow: inset 0 1px 0 rgba(255,255,255,0.12), inset 0 -1px 0 rgba(0,0,0,0.3); }
          .bar-pressure { box-shadow: 0 0 5px 1px rgba(255,20,147,0.4); }
          .bar-alt { filter: brightness(0.82); }
          .warn-badge { position: absolute; top: 1px; right: 3px; font-size: 10px; line-height: 1; color: var(--accent); pointer-events: none; font-weight: 600; }
          .bar-c-human    { background: linear-gradient(to right, #ff3faa 0%, #FF1493 12%, #FF1493 88%, #c8107a 100%); }
          .bar-c-task     { background: linear-gradient(to right, #ffc84e 0%, #FFB020 12%, #FFB020 88%, #d9941a 100%); }
          .bar-c-assistant{ background: linear-gradient(to right, #1ee8eb 0%, #00CED1 12%, #00CED1 88%, #00abb0 100%); }
          .bar-c-tool     { background: linear-gradient(to right, #22c4ff 0%, #00A8E8 12%, #00A8E8 88%, #0088c0 100%); }
          .bar-c-sidechain{ background: linear-gradient(to right, #d88fff 0%, #C97BFF 12%, #C97BFF 88%, #a85ee0 100%); }
          .bar-c-user     { background: var(--bar-user); }
          .bar-c-sidechain .lbl, .bar-c-tool .lbl { color: rgba(255,255,255,0.9); }
          .lbl {
            display: block;
            padding: 0 5px;
            line-height: #{ROW_HEIGHT}px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            color: var(--bar-text);
            font-size: #{FONT_SIZE - 1}px;
            font-weight: 600;
            pointer-events: none;
          }
          .tip { padding: 4px 8px; font-size: 11px; min-height: 22px; display: flex; align-items: baseline; flex-wrap: wrap; gap: 0; border-top: 1px solid var(--border); background: var(--bg); }
          .tip-sep { color: var(--border); padding: 0 6px; }
          .tip-tokens { color: var(--text); font-weight: 600; }
          .tip-model { color: var(--text-dim); }
          .tip-label { color: var(--text-dim); }
          .tip-code { color: var(--accent2); }
          .tip-warn { color: var(--accent); }
          .tip-prompt { flex: 1; min-width: 0; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .total-bar { background: var(--surface); border: 1px solid var(--border); border-radius: 1px; cursor: pointer; }
          .total-lbl { color: var(--text-dim) !important; font-weight: 600; letter-spacing: 0.04em; font-size: 11px; }
          .legend { padding: 2px 8px 6px; display: flex; gap: 14px; flex-wrap: wrap; }
          .legend-item { display: flex; align-items: center; gap: 5px; color: var(--text-dim); font-size: 10px; }
          .legend-swatch { display: inline-block; width: 10px; height: 10px; border-radius: 1px; flex-shrink: 0; }
          .legend-swatch.bar-compaction { background: var(--bar-compaction) !important; }
          .floattip { position: fixed; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 3px; padding: 3px 8px; font-size: 11px; font-family: inherit; pointer-events: none; display: none; white-space: nowrap; z-index: 1000; box-shadow: 0 4px 16px var(--shadow); }
          .summary-btn { background: none; border: 1px solid var(--border); color: var(--text-dim); border-radius: 3px; padding: 2px 8px; font-size: 10px; cursor: pointer; font-family: inherit; }
          .summary-btn:hover { background: var(--surface); color: var(--text); border-color: var(--accent); }
          .summary-btn.active { border-color: var(--accent); color: var(--accent); }
          .export-btn { background: none; border: 1px solid var(--border); color: var(--text-dim); border-radius: 3px; padding: 2px 8px; font-size: 10px; cursor: pointer; font-family: inherit; }
          .export-btn:hover { background: var(--surface); color: var(--accent2); border-color: var(--accent2); }
          .summary-panel { position: fixed; right: 0; top: 0; height: 100%; width: 260px; background: var(--surface); border-left: 1px solid var(--border); z-index: 500; overflow-y: auto; padding: 16px; box-shadow: -8px 0 24px var(--shadow); }
          .summary-panel-title { color: var(--accent); font-size: 12px; font-weight: 600; margin-bottom: 14px; display: flex; justify-content: space-between; align-items: center; letter-spacing: 0.04em; }
          .summary-close { background: none; border: none; color: var(--text-dim); font-size: 16px; cursor: pointer; padding: 0 2px; line-height: 1; font-family: inherit; }
          .summary-close:hover { color: var(--accent); }
          .summary-dl { display: grid; grid-template-columns: 1fr auto; gap: 8px 16px; }
          .summary-dt { color: var(--text-dim); font-size: 10px; align-self: center; }
          .summary-val { color: var(--text); font-size: 11px; font-weight: 600; text-align: right; align-self: center; }
          .summary-warn { color: var(--accent); }
        CSS
      end

      def js
        w = @canvas_width
        min_lbl_px = MIN_LABEL_PX
        <<~JS
          (function() {
            var W = #{w}, MIN_LBL_PX = #{min_lbl_px};
            var costMode = false, zoomedEl = null;
            var hmActiveIdx = -1, hmSorted = false, hmCount = #{@hm_count};
            function bars() { return Array.from(document.querySelectorAll('.bar:not(.total-bar)')); }
            function applyBar(el, nx, nw) {
              if (nx + nw <= 0 || nx >= W) {
                el.style.display = 'none';
              } else {
                el.style.display = '';
                el.style.left = (nx / W * 100) + '%';
                el.style.width = 'calc(' + (Math.max(nw, 1) / W * 100) + '% + 1px)';
                var lbl = el.querySelector('.lbl');
                if (lbl) lbl.style.display = (nw < MIN_LBL_PX) ? 'none' : '';
              }
            }
            function resetBtn() { return document.getElementById('reset-btn'); }
            function withoutTransition(fn) {
              document.querySelectorAll('.bar').forEach(function(b) { b.style.transition = 'none'; });
              fn();
              var first = document.querySelector('.bar');
              if (first) first.offsetHeight;
              document.querySelectorAll('.bar').forEach(function(b) { b.style.transition = ''; });
            }
            window.toggleTheme = function() {
              var root = document.documentElement;
              var isLight = root.getAttribute('data-theme') === 'light';
              root.setAttribute('data-theme', isLight ? 'dark' : 'light');
              var btn = document.getElementById('theme-btn');
              if (btn) btn.textContent = isLight ? '\u25D0 Light' : '\u25D1 Dark';
            };
            window.toggleSummary = function() {
              var p = document.getElementById('summary-panel');
              var btn = document.getElementById('summary-btn');
              if (!p) return;
              var shown = p.style.display !== 'none';
              p.style.display = shown ? 'none' : 'block';
              if (btn) btn.classList.toggle('active', !shown);
            };
            window.toggleCostView = function() {
              var wasZoomed = zoomedEl;
              if (wasZoomed) unzoom();
              costMode = !costMode;
              withoutTransition(function() {
                bars().forEach(function(b) {
                  var nx = costMode ? +b.getAttribute('data-cx') : +b.getAttribute('data-ox');
                  var nw = costMode ? +b.getAttribute('data-cw') : +b.getAttribute('data-ow');
                  applyBar(b, nx, nw);
                  var lbl = b.querySelector('.lbl');
                  if (lbl) {
                    var text = b.getAttribute(costMode ? 'data-cost-lbl' : 'data-token-lbl');
                    if (text !== null) lbl.textContent = text;
                  }
                });
              });
              var tl = document.getElementById('total-lbl');
              if (tl) tl.innerHTML = tl.getAttribute(costMode ? 'data-cost-text' : 'data-token-text');
              var cb = document.getElementById('cost-btn');
              if (cb) { cb.textContent = costMode ? '# Token view' : '$ Cost view'; cb.classList.toggle('active', costMode); }
              hmCells().forEach(function(c) { c.style.backgroundColor = c.getAttribute(costMode ? 'data-color-cost' : 'data-color-token'); });
              var sb = document.getElementById('hm-sort-btn');
              if (sb && hmSorted) sb.innerHTML = costMode ? '&#x21C5; Sort by cost' : '&#x21C5; Sort by tokens';
              var ramp = document.getElementById('hm-legend-ramp');
              if (ramp) ramp.style.background = costMode ? ramp.getAttribute('data-cost-grad') : ramp.getAttribute('data-token-grad');
              var lmLo = document.getElementById('hm-legend-lo');
              var lmHi = document.getElementById('hm-legend-hi');
              if (lmLo) lmLo.textContent = costMode ? 'cheap' : 'few tokens';
              if (lmHi) lmHi.textContent = costMode ? 'costly' : 'many';
              scaleHeatmap();
              if (wasZoomed) {
                if (wasZoomed.classList && wasZoomed.classList.contains('hm-cell')) {
                  openPrompt(+wasZoomed.getAttribute('data-idx'));
                } else {
                  zoom(wasZoomed);
                }
              }
            };
            window.zoom = function(el) {
              var fx = costMode ? +el.getAttribute('data-cx') : +el.getAttribute('data-ox');
              var fw = costMode ? +el.getAttribute('data-cw') : +el.getAttribute('data-ow');
              if (fw >= W - 1) { unzoom(); return; }
              var wrap = document.getElementById('flame-wrap');
              var flame = document.querySelector('.flame');
              if (!flame.getAttribute('data-orig-w')) flame.setAttribute('data-orig-w', flame.style.width);
              flame.style.width = wrap.clientWidth + 'px';
              wrap.scrollLeft = 0;
              bars().forEach(function(b) {
                if (!b.getAttribute('ox')) {
                  b.setAttribute('ox', costMode ? +b.getAttribute('data-cx') : +b.getAttribute('data-ox'));
                  b.setAttribute('ow', costMode ? +b.getAttribute('data-cw') : +b.getAttribute('data-ow'));
                }
                applyBar(b, (+b.getAttribute('ox') - fx) / fw * W, +b.getAttribute('ow') / fw * W);
              });
              var btn = resetBtn(); if (btn) btn.style.display = 'inline-block';
              zoomedEl = el;
            };
            window.unzoom = function() {
              var flame = document.querySelector('.flame');
              var origW = flame.getAttribute('data-orig-w');
              if (origW) { flame.style.width = origW; flame.removeAttribute('data-orig-w'); }
              bars().forEach(function(b) {
                var ox = b.getAttribute('ox');
                if (ox) {
                  applyBar(b, +ox, +b.getAttribute('ow'));
                  b.removeAttribute('ox');
                  b.removeAttribute('ow');
                }
              });
              var btn = resetBtn(); if (btn) btn.style.display = 'none';
              zoomedEl = null;
            };
            // resetZoom: if sub-zoomed inside a prompt → unzoom back to prompt view;
            // if viewing a prompt (or full overview) → close back to heatmap
            window.resetZoom = function() {
              if (zoomedEl && zoomedEl.classList && !zoomedEl.classList.contains('hm-cell')) {
                unzoom();
              } else {
                closePrompt();
              }
            };
            function escSVG(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
            window.exportSVG = function() {
              var SVG_W = 1600, HDR = 28, MIN_H = 400;
              var flame = document.querySelector('.flame');
              var flameH = parseFloat(flame.style.height) || flame.offsetHeight;
              var svgH = Math.max(MIN_H, Math.round(flameH) + HDR);
              var yOffset = svgH - Math.round(flameH) - HDR; // push bars to bottom
              var allBars = Array.from(document.querySelectorAll('.flame .bar')).filter(function(b) { return b.style.display !== 'none'; });
              if (!allBars.length) return;
              var st = getComputedStyle(document.documentElement);
              var bg = st.getPropertyValue('--bg').trim() || '#000';
              var surface = st.getPropertyValue('--surface').trim() || '#0a0a14';
              var border = st.getPropertyValue('--border').trim() || '#1a1a2e';
              var textDim = st.getPropertyValue('--text-dim').trim() || '#8892a0';
              var barText = st.getPropertyValue('--bar-text').trim() || '#000';
              var summaryEl = document.querySelector('.summary');
              var summaryStr = summaryEl ? summaryEl.textContent.trim() : '';
              var defs = [], rects = [], texts = [];
              rects.push('<rect x="0" y="0" width="' + SVG_W + '" height="' + HDR + '" fill="' + surface + '"/>');
              rects.push('<line x1="0" y1="' + HDR + '" x2="' + SVG_W + '" y2="' + HDR + '" stroke="' + border + '" stroke-width="1"/>');
              texts.push('<text x="8" y="18" font-family="monospace" font-size="11" fill="' + textDim + '">' + escSVG(summaryStr) + '</text>');
              allBars.forEach(function(bar, i) {
                var x = Math.round(parseFloat(bar.style.left) / 100 * SVG_W);
                var w = Math.max(1, Math.round(parseFloat(bar.style.width) / 100 * SVG_W));
                var y = Math.round(parseFloat(bar.style.top)) + HDR + yOffset;
                var h = Math.round(parseFloat(getComputedStyle(bar).height));
                if (isNaN(x) || isNaN(y) || isNaN(w) || h <= 0) return;
                var fill = getComputedStyle(bar).backgroundColor;
                var cid = 'c' + i;
                defs.push('<clipPath id="' + cid + '"><rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '"/></clipPath>');
                rects.push('<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" fill="' + fill + '"/>');
                var lbl = bar.querySelector('.lbl');
                if (lbl && lbl.style.display !== 'none' && w > 28 && lbl.textContent.trim()) {
                  var isTotal = bar.classList.contains('total-bar');
                  texts.push('<text x="' + (x+3) + '" y="' + (y + h/2 + 4) + '" font-family="monospace" font-size="11" fill="' + (isTotal ? textDim : barText) + '" font-weight="' + (isTotal ? '600' : '400') + '" clip-path="url(#' + cid + ')">' + escSVG(lbl.textContent) + '</text>');
                }
              });
              var svg = '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="' + SVG_W + '" height="' + svgH + '"><rect width="100%" height="100%" fill="' + bg + '"/><defs>' + defs.join('') + '</defs>' + rects.join('') + texts.join('') + '</svg>';
              var a = document.createElement('a');
              a.href = URL.createObjectURL(new Blob([svg], {type: 'image/svg+xml'}));
              a.download = 'token-lens.svg';
              document.body.appendChild(a); a.click(); document.body.removeChild(a);
            };
            function esc(t) { return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
            window.tip = function(s, prompt) {
              var el = document.getElementById('tip');
              if (!el) return;
              if (!s && !prompt) { el.innerHTML = '<span class="tip-label">Hover for details \u00b7 Click to zoom</span>'; return; }
              var sep = '<span class="tip-sep">\u00b7</span>';
              var parts = s ? s.split(' | ').filter(Boolean) : [];
              var html = parts.map(function(p, i) {
                var e = esc(p);
                if (p.charAt(0) === '\u26a0') return '<span class="tip-warn">' + e + '</span>';
                if (i === 0 && p.indexOf('tokens') !== -1) return '<span class="tip-tokens">' + e + '</span>';
                if (p.indexOf('claude-') !== -1 || /^(haiku|sonnet|opus)/.test(p)) return '<span class="tip-model">' + e + '</span>';
                if (/^[^:]*:\s/.test(p)) return '<span class="tip-label">' + e + '</span>';
                return '<span class="tip-code">' + e + '</span>';
              }).join(sep);
              if (prompt) html += (html ? sep : '') + '<span class="tip-prompt">' + esc(prompt) + '</span>';
              el.innerHTML = html;
            };
            var mx = 0, my = 0;
            document.addEventListener('mousemove', function(e) {
              mx = e.clientX; my = e.clientY;
              var ft = document.getElementById('ftip');
              if (ft && ft.style.display !== 'none') {
                ft.style.left = (mx + 14) + 'px';
                ft.style.top = (my - 38) + 'px';
              }
            });
            document.addEventListener('mouseover', function(e) {
              var bar = e.target.closest && e.target.closest('.bar:not(.total-bar)');
              var ft = document.getElementById('ftip');
              if (!ft) return;
              if (bar) {
                var d = bar.getAttribute('data-ftip');
                if (d) { ft.textContent = d; ft.style.display = 'block'; ft.style.left = (mx + 14) + 'px'; ft.style.top = (my - 38) + 'px'; }
              }
            });
            document.addEventListener('mouseout', function(e) {
              var bar = e.target.closest && e.target.closest('.bar:not(.total-bar)');
              if (bar) { var ft = document.getElementById('ftip'); if (ft) ft.style.display = 'none'; }
            });
            // Disable transitions on initial load
            document.querySelectorAll('.bar').forEach(function(b) { b.style.transition = 'none'; });
            requestAnimationFrame(function() { requestAnimationFrame(function() {
              document.querySelectorAll('.bar').forEach(function(b) { b.style.transition = ''; });
            }); });
            // Heatmap
            function hmCells() { return Array.from(document.querySelectorAll('.hm-cell')); }
            window.hmTip = function(el) { tip(el.getAttribute('data-tip'), el.getAttribute('data-tip-prompt')); };
            function zoomToRoot(cell) {
              var fx = costMode ? +cell.getAttribute('data-cx') : +cell.getAttribute('data-ox');
              var fw = costMode ? +cell.getAttribute('data-cw') : +cell.getAttribute('data-ow');
              if (fw <= 0) return;
              var wrap = document.getElementById('flame-wrap');
              var flame = document.querySelector('.flame');
              if (!flame.getAttribute('data-orig-w')) flame.setAttribute('data-orig-w', flame.style.width);
              flame.style.width = wrap.clientWidth + 'px';
              wrap.scrollLeft = 0;
              bars().forEach(function(b) {
                if (!b.getAttribute('ox')) {
                  b.setAttribute('ox', costMode ? +b.getAttribute('data-cx') : +b.getAttribute('data-ox'));
                  b.setAttribute('ow', costMode ? +b.getAttribute('data-cw') : +b.getAttribute('data-ow'));
                }
                applyBar(b, (+b.getAttribute('ox') - fx) / fw * W, +b.getAttribute('ow') / fw * W);
              });
              zoomedEl = cell;
            }
            window.openPrompt = function(idx) {
              hmActiveIdx = idx;
              var hm = document.getElementById('heatmap');
              if (hm) hm.classList.add('hm-strip');
              hmCells().forEach(function(c) { c.classList.toggle('hm-active', +c.getAttribute('data-idx') === idx); });
              var fw = document.getElementById('flame-wrap');
              if (fw) fw.style.display = '';
              var lg = document.getElementById('legend'); if (lg) lg.style.display = '';
              var back = document.getElementById('hm-back');
              if (back) back.style.display = '';
              var cell = document.querySelector('.hm-cell[data-idx="' + idx + '"]');
              if (cell) { withoutTransition(function() { zoomToRoot(cell); }); }
              var btn = resetBtn(); if (btn) btn.style.display = 'none';
            };
            window.closePrompt = function() {
              hmActiveIdx = -1;
              unzoom();
              var fw = document.getElementById('flame-wrap');
              if (fw) fw.style.display = 'none';
              var lg = document.getElementById('legend'); if (lg) lg.style.display = 'none';
              var hm = document.getElementById('heatmap');
              if (hm) hm.classList.remove('hm-strip');
              hmCells().forEach(function(c) { c.classList.remove('hm-active'); });
              var back = document.getElementById('hm-back');
              if (back) back.style.display = 'none';
              var si = document.getElementById('hm-search');
              if (si) { si.value = ''; filterHeatmap(''); }
            };
            window.sortHeatmap = function() {
              hmSorted = !hmSorted;
              var grid = document.getElementById('hm-grid');
              if (!grid) return;
              var cells = hmCells();
              if (hmSorted) {
                cells.sort(function(a, b) {
                  var av = costMode ? parseFloat(a.getAttribute('data-cost')) : parseInt(a.getAttribute('data-tokens'));
                  var bv = costMode ? parseFloat(b.getAttribute('data-cost')) : parseInt(b.getAttribute('data-tokens'));
                  return bv - av;
                });
              } else {
                cells.sort(function(a, b) { return parseInt(a.getAttribute('data-idx')) - parseInt(b.getAttribute('data-idx')); });
              }
              cells.forEach(function(c) { grid.appendChild(c); });
              scaleHeatmap();
              var btn = document.getElementById('hm-sort-btn');
              if (btn) btn.classList.toggle('active', hmSorted);
            };
            window.filterHeatmap = function(query) {
              var q = query.toLowerCase().trim();
              hmCells().forEach(function(c) {
                var match = !q || (c.getAttribute('data-prompt') || '').indexOf(q) !== -1;
                c.classList.toggle('hm-dimmed', !match);
              });
              scaleHeatmap();
            };
            function scaleHeatmap() {
              var hm = document.getElementById('heatmap');
              if (hm && hm.classList.contains('hm-strip')) return;
              var allCells = hmCells();
              var cells = allCells.filter(function(c) { return !c.classList.contains('hm-dimmed'); });
              var n = cells.length || 1;
              var maxCell = Math.min(96, Math.max(36, Math.floor(1400 / Math.sqrt(n))));
              var minCell = 16;
              var vals = cells.map(function(c) {
                return costMode ? parseFloat(c.getAttribute('data-cost')) : parseInt(c.getAttribute('data-tokens'));
              });
              var maxVal = Math.max.apply(null, vals) || 1;
              var minVal = Math.min.apply(null, vals) || 0;
              cells.forEach(function(c, i) {
                var v = vals[i];
                var t = (maxVal === minVal) ? 0.5 : (v - minVal) / (maxVal - minVal);
                var sz = Math.round(minCell + (maxCell - minCell) * Math.sqrt(t));
                c.style.width = sz + 'px';
                c.style.height = sz + 'px';
                var lbl = c.querySelector('.hm-idx');
                if (lbl) lbl.style.display = (sz < 24) ? 'none' : '';
              });
              allCells.filter(function(c) { return c.classList.contains('hm-dimmed'); }).forEach(function(c) {
                c.style.width = minCell + 'px';
                c.style.height = minCell + 'px';
              });
            }
            document.addEventListener('keydown', function(e) {
              if (e.key === 'Enter' && document.activeElement && document.activeElement.classList.contains('hm-cell')) {
                e.preventDefault();
                openPrompt(+document.activeElement.getAttribute('data-idx'));
                return;
              }
              if (hmActiveIdx < 0) return;
              if (e.target && e.target.tagName === 'INPUT') return;
              if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
                e.preventDefault();
                if (hmActiveIdx > 0) openPrompt(hmActiveIdx - 1);
              } else if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
                e.preventDefault();
                if (hmActiveIdx < hmCount - 1) openPrompt(hmActiveIdx + 1);
              } else if (e.key === 'Escape') {
                e.preventDefault();
                closePrompt();
              }
            });
            scaleHeatmap();
          })();
        JS
      end
    end
  end
end
