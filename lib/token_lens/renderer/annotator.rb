# frozen_string_literal: true

module TokenLens
  module Renderer
    class Annotator
      def annotate(nodes, depth = 0)
        nodes.each do |node|
          node[:depth] = depth
          annotate(node[:children], depth + 1)
          child_tokens = node[:children].sum { |c| c[:subtree_tokens] }
          node[:subtree_tokens] = [node[:token].total_tokens, 1].max + child_tokens
        end
        nodes
      end
    end
  end
end
