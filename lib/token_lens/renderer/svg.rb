# frozen_string_literal: true

module TokenLens
  module Renderer
    class Svg
      CANVAS_WIDTH = 1200
      ROW_HEIGHT = 24
      PADDING = 4
      MIN_TEXT_WIDTH = 40
      DETAILS_HEIGHT = 20

      COLORS = {
        user: "#6c7086",
        assistant: "#89b4fa",
        assistant_tool: "#fab387",
        sidechain: "#a6e3a1"
      }.freeze

      def initialize(canvas_width: CANVAS_WIDTH)
        @canvas_width = canvas_width
      end

      def render(nodes)
        all_nodes = flatten(nodes).reject { |n| n[:w] <= 1 }
        max_depth = all_nodes.map { |n| n[:depth] }.max || 0
        height = (max_depth + 1) * ROW_HEIGHT + PADDING * 2 + DETAILS_HEIGHT

        lines = []
        lines << header(height)
        lines << inline_script
        all_nodes.each { |n| lines << group(n) }
        lines << details_element(height)
        lines << "</svg>"
        lines.join("\n")
      end

      private

      def flatten(nodes)
        nodes.flat_map { |n| [n, *flatten(n[:children])] }
      end

      def header(height)
        <<~SVG.chomp
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{@canvas_width} #{height}" width="#{@canvas_width}" height="#{height}">
          <rect width="100%" height="100%" fill="#1e1e2e"/>
        SVG
      end

      def group(node)
        w = [node[:w] - 1, 0].max
        y = node[:y] + PADDING
        lbl = label(node)
        info = escape_js(tooltip(node))
        text_hidden = (w < MIN_TEXT_WIDTH) ? " display=\"none\"" : ""
        [
          %(<g class="f" data-x="#{node[:x]}" data-w="#{node[:w]}" onclick="zoom(this)" onmouseover="tip('#{info}')" onmouseout="tip('')">),
          %(<title>#{lbl}</title>),
          %(<rect x="#{node[:x]}" y="#{y}" width="#{w}" height="#{ROW_HEIGHT - 2}" fill="#{color(node)}" rx="2"/>),
          %(<text x="#{node[:x] + 4}" y="#{y + 14}" font-size="11" font-family="monospace" fill="#1e1e2e"#{text_hidden}>#{lbl}</text>),
          "</g>"
        ].join("\n")
      end

      def details_element(height)
        y = height - DETAILS_HEIGHT + 14
        %(<text id="tip" x="4" y="#{y}" font-size="11" font-family="monospace" fill="#cdd6f4">\u00a0</text>)
      end

      def inline_script
        w = @canvas_width
        min_w = MIN_TEXT_WIDTH
        <<~JS.chomp
          <script type="text/ecmascript"><![CDATA[
          (function() {
            var W = #{w}, MIN_W = #{min_w};
            function frames() { return Array.from(document.querySelectorAll("g.f")); }
            function cache() {
              frames().forEach(function(f) {
                if (!f.getAttribute("ox")) {
                  f.setAttribute("ox", f.getAttribute("data-x"));
                  f.setAttribute("ow", f.getAttribute("data-w"));
                }
              });
            }
            function apply(f, nx, nw) {
              var r = f.querySelector("rect"), t = f.querySelector("text");
              if (nx + nw <= 0 || nx >= W) {
                r.setAttribute("width", 0);
                if (t) t.setAttribute("display", "none");
              } else {
                r.setAttribute("x", nx);
                r.setAttribute("width", Math.max(nw - 1, 0));
                if (t) {
                  t.setAttribute("x", nx + 4);
                  t.setAttribute("display", nw >= MIN_W ? "" : "none");
                }
              }
            }
            window.zoom = function(g) {
              cache();
              var fx = +g.getAttribute("ox"), fw = +g.getAttribute("ow");
              if (fw >= W - 1) { unzoom(); return; }
              frames().forEach(function(f) {
                apply(f, (+f.getAttribute("ox") - fx) / fw * W, +f.getAttribute("ow") / fw * W);
              });
            };
            window.unzoom = function() {
              frames().forEach(function(f) {
                var ox = f.getAttribute("ox");
                if (ox) apply(f, +ox, +f.getAttribute("ow"));
              });
            };
            window.tip = function(s) {
              var el = document.getElementById("tip");
              if (el) el.textContent = s || "\u00a0";
            };
          })();
          ]]></script>
        JS
      end

      def color(node)
        t = node[:token]
        return COLORS[:sidechain] if t.is_sidechain
        case t.role
        when "user" then COLORS[:user]
        when "assistant"
          t.tool_uses.any? ? COLORS[:assistant_tool] : COLORS[:assistant]
        else COLORS[:user]
        end
      end

      def label(node)
        t = node[:token]
        if t.role == "assistant" && t.tool_uses.any?
          t.tool_uses.map { |tool| tool["name"] }.join(", ")
        elsif t.role == "assistant"
          "out: #{t.output_tokens}"
        else
          t.role
        end
      end

      def tooltip(node)
        t = node[:token]
        parts = []
        parts << t.model if t.model
        parts << "in:#{t.input_tokens}" if t.input_tokens > 0
        parts << "cached:#{t.cache_read_tokens}" if t.cache_read_tokens > 0
        parts << "+cache:#{t.cache_creation_tokens}" if t.cache_creation_tokens > 0
        parts << "out:#{t.output_tokens}"
        parts << "[sidechain]" if t.is_sidechain
        parts.join(" | ")
      end

      def escape_js(str)
        str.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      end
    end
  end
end
