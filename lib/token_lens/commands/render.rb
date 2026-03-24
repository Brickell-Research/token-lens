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
      def initialize(output:, file_path: nil)
        @file_path = file_path
        @output = output
      end

      def run
        path = resolve_path
        warn "Rendering #{path}"
        tree = Parser.new(file_path: path).parse
        tree = Renderer::Reshaper.new.reshape(tree)
        tree.sort_by! { |n| n[:token].timestamp || "" }
        Renderer::Annotator.new.annotate(tree)
        canvas_width = Renderer::Layout.new.layout(tree)
        html = Renderer::Html.new(canvas_width: canvas_width).render(tree)
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
        Session.active_or_latest_jsonl
      end
    end
  end
end
