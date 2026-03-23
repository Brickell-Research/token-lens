# frozen_string_literal: true

require "thor"
require "token_lens/commands/record"
require "token_lens/commands/render"

module TokenLens
  class CLI < Thor
    desc "record", "Tail the active session and auto-save a capture file"
    option :duration_in_seconds, type: :numeric, default: 30, desc: "Seconds to record"
    option :project_dir, type: :string, desc: "Working directory of the Claude Code session to record (default: auto-detect)"
    option :output, type: :string, desc: "Save path for the capture (default: ~/.token-lens/sessions/<timestamp>.json)"
    def record
      Commands::Record.new(
        duration_in_seconds: options[:duration_in_seconds],
        project_dir: options[:project_dir],
        output: options[:output]
      ).run
    end

    desc "render", "Render a captured session as a flame graph"
    option :file_path, type: :string, desc: "Path to the captured JSON file (default: most recent session)"
    option :output, type: :string, default: "flame.html", desc: "Output HTML path"
    def render
      Commands::Render.new(file_path: options[:file_path], output: options[:output]).run
    end
  end
end
