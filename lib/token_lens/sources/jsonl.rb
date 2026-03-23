# frozen_string_literal: true

require "json"
require "token_lens/session"

module TokenLens
  module Sources
    class Jsonl
      def initialize(queue)
        @queue = queue
        @path = Session.active_jsonl
      end

      def start
        warn "  [jsonl] tailing #{@path.basename}"
        last_pos = File.size(@path)

        loop do
          sleep 0.1
          current_size = File.size(@path)
          next if current_size == last_pos

          File.open(@path) do |f|
            f.seek(last_pos)
            f.each_line do |line|
              event = JSON.parse(line)
              @queue << {source: "jsonl", event: event}
            end
            last_pos = f.pos
          end
        end
      end
    end
  end
end
