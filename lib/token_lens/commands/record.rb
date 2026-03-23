# frozen_string_literal: true

require "json"
require "fileutils"
require "token_lens/sources/jsonl"

module TokenLens
  module Commands
    class Record
      SESSIONS_DIR = Pathname.new(Dir.home).join(".token-lens", "sessions")

      def initialize(duration_in_seconds:, project_dir: nil, output: nil)
        @duration_in_seconds = duration_in_seconds
        @project_dir = project_dir
        @output = output
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
        path = save_path
        FileUtils.mkdir_p(path.dirname)
        path.write(JSON.generate(events))
        warn "Saved to #{path}"
        exit 0
      end

      def save_path
        return Pathname.new(@output) if @output
        timestamp = Time.now.strftime("%Y-%m-%d_%H-%M-%S")
        SESSIONS_DIR.join("#{timestamp}.json")
      end
    end
  end
end
