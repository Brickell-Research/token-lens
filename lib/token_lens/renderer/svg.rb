# frozen_string_literal: true

module TokenLens
  module Renderer
    class Svg
      CANVAS_WIDTH = 1200
      ROW_HEIGHT = 24
      PADDING = 4
      MIN_TEXT_WIDTH = 40

      COLORS = {
        user: "#6c7086",
        assistant: "#89b4fa",
        assistant_tool: "#fab387"
      }.freeze

      def initialize(canvas_width: CANVAS_WIDTH)
        @canvas_width = canvas_width
      end

      def render(nodes)
        all_nodes = flatten(nodes)
        max_depth = all_nodes.map { |n| n[:depth] }.max || 0
        height = (max_depth + 1) * ROW_HEIGHT + PADDING * 2

        lines = []
        lines << header(height)
        all_nodes.each { |n| lines << rect(n) }
        all_nodes.each { |n| lines << text(n) if n[:w] >= MIN_TEXT_WIDTH }
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

      def rect(node)
        w = [node[:w] - 1, 0].max
        y = node[:y] + PADDING
        %(<rect x="#{node[:x]}" y="#{y}" width="#{w}" height="#{ROW_HEIGHT - 2}" fill="#{color(node)}" rx="2"/>)
      end

      def text(node)
        y = node[:y] + PADDING + 14
        %(<text x="#{node[:x] + 4}" y="#{y}" font-size="11" font-family="monospace" fill="#1e1e2e">#{label(node)}</text>)
      end

      def color(node)
        case node[:token].role
        when "user" then COLORS[:user]
        when "assistant"
          node[:token].tool_uses.any? ? COLORS[:assistant_tool] : COLORS[:assistant]
        else COLORS[:user]
        end
      end

      def label(node)
        if node[:token].role == "assistant" && node[:token].tool_uses.any?
          node[:token].tool_uses.map { |t| t["name"] }.join(", ")
        else
          "#{node[:token].role} (#{node[:token].total_tokens})"
        end
      end
    end
  end
end
