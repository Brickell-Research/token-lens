# frozen_string_literal: true

require "token_lens/parser"
require "token_lens/renderer/reshaper"
require "token_lens/renderer/annotator"
require "token_lens/renderer/layout"
require "token_lens/renderer/html"

module TokenLens
  module Commands
    class Render
      def initialize(file_path: nil, output:)
        @file_path = file_path
        @output = output
      end

      def run
        path = resolve_path
        warn "Rendering #{path}"
        tree = Parser.new(file_path: path).parse
        tree = Renderer::Reshaper.new.reshape(tree)
        Renderer::Annotator.new.annotate(tree)
        Renderer::Layout.new.layout(tree)
        html = Renderer::Html.new.render(tree)
        File.write(@output, html)
        warn "Wrote #{@output}"
      end

      private

      def resolve_path
        return @file_path if @file_path
        sessions = Pathname.new(Dir.home).join(".token-lens", "sessions")
        all = sessions.glob("*.json").sort_by(&:mtime)
        raise "No saved sessions found in #{sessions}. Run `token-lens record` first." if all.empty?
        all.last
      end
    end
  end
end
