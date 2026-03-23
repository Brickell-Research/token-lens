# frozen_string_literal: true

require "thor"
require "token_lens/commands/record"
require "token_lens/commands/parse"
require "token_lens/commands/render"

module TokenLens
  class CLI < Thor
    desc "record", "Tail the active session and capture events to stdout"
    option :duration_in_seconds, type: :numeric, default: 30, desc: "Seconds to record"
    def record
      Commands::Record.new(duration_in_seconds: options[:duration_in_seconds]).run
    end

    desc "render", "Render a captured session as a flame graph SVG"
    option :file_path, type: :string, required: true, desc: "Path to the captured JSON file"
    option :output, type: :string, default: "flame.svg", desc: "Output SVG path"
    def render
      Commands::Render.new(file_path: options[:file_path], output: options[:output]).run
    end

    desc "parse", "Parse a token-lens JSON file"
    option :file_path, type: :string, desc: "Path to the JSON file to parse"
    def parse
      Commands::Parse.new(file_path: options[:file_path]).run
    end
  end
end
