# frozen_string_literal: true

module TokenLens
  module Renderer
    class Annotator
      def annotate(nodes, depth = 0)
        nodes.each do |node|
          node[:depth] = depth
          annotate(node[:children], depth + 1)
          child_tokens = node[:children].sum { |c| c[:subtree_tokens] }
          child_cost = node[:children].sum { |c| c[:subtree_cost] }
          node[:subtree_tokens] = [node[:token].display_width, 1].max + child_tokens
          node[:subtree_cost] = node[:token].cost_usd + child_cost
        end
        nodes
      end
    end
  end
end
