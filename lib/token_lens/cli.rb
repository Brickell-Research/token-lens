# frozen_string_literal: true

require "thor"
require "token_lens/commands/record"

module TokenLens
  class CLI < Thor
    desc "record", "Tail the active session and capture events to stdout"
    option :duration_in_seconds, type: :numeric, default: 30, desc: "Seconds to record"
    def record
      Commands::Record.new(duration_in_seconds: options[:duration_in_seconds]).run
    end
  end
end
