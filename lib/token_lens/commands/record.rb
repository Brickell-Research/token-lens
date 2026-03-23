# frozen_string_literal: true

require "json"
require "token_lens/sources/jsonl"

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

        thread = Thread.new { Sources::Jsonl.new(queue).start }
        drain_thread = Thread.new { loop { events << queue.pop } }

        sleep @duration_in_seconds

        thread.kill
        drain_thread.kill
        events << queue.pop until queue.empty?

        warn "Captured #{events.size} events"
        $stdout.puts JSON.generate(events)
      end
    end
  end
end
