# frozen_string_literal: true

require "token_lens/parser"
require "token_lens/renderer/annotator"
require "token_lens/renderer/layout"
require "token_lens/renderer/svg"

module TokenLens
  module Commands
    class Render
      def initialize(file_path:, output:)
        @file_path = file_path
        @output = output
      end

      def run
        tree = Parser.new(file_path: @file_path).parse
        tree = collapse_user_nodes(tree)
        Renderer::Annotator.new.annotate(tree)
        Renderer::Layout.new.layout(tree)
        svg = Renderer::Svg.new.render(tree)
        File.write(@output, svg)
        warn "Wrote #{@output}"
      end

      private

      # Remove user (tool-result) nodes, hoisting their children up.
      # This leaves only assistant nodes in the tree for visualization.
      def collapse_user_nodes(nodes)
        nodes.flat_map do |node|
          if node[:token].role == "user"
            collapse_user_nodes(node[:children])
          else
            node[:children] = collapse_user_nodes(node[:children])
            [node]
          end
        end
      end
    end
  end
end
