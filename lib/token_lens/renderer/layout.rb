# frozen_string_literal: true

module TokenLens
  module Renderer
    class Layout
      CANVAS_WIDTH = 1200
      ROW_HEIGHT = 32

      def initialize(canvas_width: CANVAS_WIDTH)
        @canvas_width = canvas_width
      end

      def layout(nodes)
        max_depth = all_nodes(nodes).map { |n| n[:depth] }.max || 0
        total = nodes.sum { |n| n[:subtree_tokens] }
        scale = (total > 0) ? @canvas_width.to_f / total : 1.0
        position(nodes, x: 0, scale: scale, max_depth: max_depth)

        total_cost = nodes.sum { |n| n[:subtree_cost] }
        cost_scale = (total_cost > 0) ? @canvas_width.to_f / total_cost : 1.0
        position_cost(nodes, x: 0, scale: cost_scale, max_depth: max_depth)

        nodes
      end

      private

      # Bottom-up layout: roots at bottom (y = max_depth * ROW_HEIGHT),
      # deepest children at top (y = 0).
      def position(nodes, x:, scale:, max_depth:)
        cursor = x
        nodes.each do |node|
          node[:x] = cursor
          node[:y] = (max_depth - node[:depth]) * ROW_HEIGHT
          node[:w] = (node[:subtree_tokens] * scale).round
          position(node[:children], x: cursor, scale: scale, max_depth: max_depth)
          cursor += node[:w]
        end
      end

      def position_cost(nodes, x:, scale:, max_depth:)
        cursor = x
        nodes.each do |node|
          node[:cost_x] = cursor
          node[:cost_w] = (node[:subtree_cost] * scale).round
          position_cost(node[:children], x: cursor, scale: scale, max_depth: max_depth)
          cursor += node[:cost_w]
        end
      end

      def all_nodes(nodes)
        nodes.flat_map { |n| [n, *all_nodes(n[:children])] }
      end
    end
  end
end
