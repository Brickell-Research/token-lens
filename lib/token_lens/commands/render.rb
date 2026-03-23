# frozen_string_literal: true

require "token_lens/parser"
require "token_lens/renderer/reshaper"
require "token_lens/renderer/annotator"
require "token_lens/renderer/layout"
require "token_lens/renderer/html"

module TokenLens
  module Commands
    class Render
      def initialize(file_path:, output:)
        @file_path = file_path
        @output = output
      end

      def run
        tree = Parser.new(file_path: @file_path).parse
        tree = Renderer::Reshaper.new.reshape(tree)
        Renderer::Annotator.new.annotate(tree)
        Renderer::Layout.new.layout(tree)
        html = Renderer::Html.new.render(tree)
        File.write(@output, html)
        warn "Wrote #{@output}"
      end
    end
  end
end
