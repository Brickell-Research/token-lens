# frozen_string_literal: true

require "token_lens/parser"
require "token_lens/renderer/reshaper"
require "token_lens/renderer/annotator"
require "token_lens/renderer/layout"
require "token_lens/renderer/html"
require "token_lens/session"

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
        saved = sessions.glob("*.json").max_by(&:mtime)
        return saved if saved
        warn "No saved captures found — reading active Claude Code session directly"
        Session.latest_jsonl
      end
    end
  end
end
