# frozen_string_literal: true

require "json"
require "token_lens/sources/jsonl"

module TokenLens
  module Commands
    class Record
      def initialize(duration_in_seconds:, project_dir: nil)
        @duration_in_seconds = duration_in_seconds
        @project_dir = project_dir
      end

      def run
        warn "Recording for #{@duration_in_seconds}s... (Ctrl+C to stop early)"

        queue = Queue.new
        events = []

        thread = Thread.new { Sources::Jsonl.new(queue, project_dir: @project_dir).start }
        drain_thread = Thread.new { loop { events << queue.pop } }

        trap("INT") { finish(thread, drain_thread, queue, events) }
        trap("TERM") { finish(thread, drain_thread, queue, events) }

        sleep @duration_in_seconds
        finish(thread, drain_thread, queue, events)
      end

      private

      def finish(thread, drain_thread, queue, events)
        thread.kill
        drain_thread.kill
        events << queue.pop until queue.empty?
        warn "\nCaptured #{events.size} events"
        $stdout.puts JSON.generate(events)
        exit 0
      end
    end
  end
end
