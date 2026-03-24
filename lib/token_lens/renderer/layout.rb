# frozen_string_literal: true

module TokenLens
  module Renderer
    class Layout
      CANVAS_WIDTH = 1200
      ROW_HEIGHT = 32
      MIN_THREAD_WIDTH = 80  # minimum pixels per root thread so slivers are readable

      def initialize(canvas_width: CANVAS_WIDTH)
        @canvas_width = canvas_width
      end

      def layout(nodes)
        max_depth = all_nodes(nodes).map { |n| n[:depth] }.max || 0
        effective_width = [@canvas_width, nodes.length * MIN_THREAD_WIDTH].max

        total = nodes.sum { |n| n[:subtree_tokens] }
        scale = (total > 0) ? effective_width.to_f / total : 1.0
        position(nodes, x: 0, scale: scale, max_depth: max_depth)

        total_cost = nodes.sum { |n| n[:subtree_cost] }
        cost_scale = (total_cost > 0) ? effective_width.to_f / total_cost : 1.0
        position_cost(nodes, x: 0, scale: cost_scale, max_depth: max_depth)

        effective_width
      end

      private

      # Bottom-up layout: roots at bottom (y = max_depth * ROW_HEIGHT),
      # deepest children at top (y = 0).
      def position(nodes, x:, scale:, max_depth:)
        cursor = x.to_f
        nodes.each do |node|
          start = cursor.round
          cursor += node[:subtree_tokens] * scale
          node[:x] = start
          node[:y] = (max_depth - node[:depth]) * ROW_HEIGHT
          node[:w] = cursor.round - start
          position(node[:children], x: node[:x], scale: scale, max_depth: max_depth)
        end
      end

      def position_cost(nodes, x:, scale:, max_depth:)
        cursor = x.to_f
        nodes.each do |node|
          start = cursor.round
          cursor += node[:subtree_cost] * scale
          node[:cost_x] = start
          node[:cost_w] = cursor.round - start
          position_cost(node[:children], x: node[:cost_x], scale: scale, max_depth: max_depth)
        end
      end

      def all_nodes(nodes)
        nodes.flat_map { |n| [n, *all_nodes(n[:children])] }
      end
    end
  end
end
