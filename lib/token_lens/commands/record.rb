# frozen_string_literal: true

require "json"
require "token_lens/sources/jsonl"
require "token_lens/sources/otlp"

module TokenLens
  module Commands
    class Record
      def initialize(duration_in_seconds:)
        @duration_in_seconds = duration_in_seconds
      end

      def run
        warn "Recording for #{@duration_in_seconds}s..."

        queue = Queue.new
        events = []

        threads = [
          Thread.new { Sources::Jsonl.new(queue).start },
          Thread.new { Sources::Otlp.new(queue).start }
        ]

        drain_thread = Thread.new { loop { events << queue.pop } }

        sleep @duration_in_seconds

        threads.each(&:kill)
        drain_thread.kill
        events << queue.pop until queue.empty?

        jsonl_count = events.count { |e| e[:source] == "jsonl" }
        otlp_count = events.count { |e| e[:source] == "otlp" }
        warn "Captured #{events.size} events (#{jsonl_count} jsonl, #{otlp_count} otlp)"
        $stdout.puts JSON.generate(events)
      end
    end
  end
end
