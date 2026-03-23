# frozen_string_literal: true

module TokenLens
  module Renderer
    class Layout
      CANVAS_WIDTH = 1200
      ROW_HEIGHT = 24

      def initialize(canvas_width: CANVAS_WIDTH)
        @canvas_width = canvas_width
      end

      def layout(nodes)
        total = nodes.sum { |n| n[:subtree_tokens] }
        scale = (total > 0) ? @canvas_width.to_f / total : 1.0
        position(nodes, x: 0, scale: scale)
        nodes
      end

      private

      def position(nodes, x:, scale:)
        cursor = x
        nodes.each do |node|
          node[:x] = cursor
          node[:y] = node[:depth] * ROW_HEIGHT
          node[:w] = (node[:subtree_tokens] * scale).round
          position(node[:children], x: cursor, scale: scale)
          cursor += node[:w]
        end
      end
    end
  end
end
