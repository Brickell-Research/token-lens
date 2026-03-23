# frozen_string_literal: true

require "json"
require "token_lens/session"

module TokenLens
  module Commands
    class Record
      def initialize(duration_in_seconds:)
        @duration_in_seconds = duration_in_seconds
      end

      def run
        path = Session.active_jsonl
        warn "Recording #{path.basename} for #{@duration_in_seconds}s..."

        events = []
        # cheap multi-threaded tailing such that events are collected concurrently with minimal blocking
        # while the main thread sleeps for the duration of the recording
        thread = Thread.new { Session.tail(path) { |event| events << event } }
        sleep @duration_in_seconds
        thread.kill

        warn "Captured #{events.size} events"
        $stdout.puts JSON.generate(events)
      end
    end
  end
end
