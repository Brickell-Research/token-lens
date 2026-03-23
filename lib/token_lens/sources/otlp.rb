# frozen_string_literal: true

require "json"
require "webrick"

module TokenLens
  module Sources
    class Otlp
      PORT = 4318
      NO_DATA_TIMEOUT = 10 # seconds before warning

      def initialize(queue)
        @queue = queue
        @last_received_at = nil
      end

      def start
        warn "  [otlp] listening on http://localhost:#{PORT}/v1/logs"
        server = build_server
        monitor_thread = start_no_data_monitor
        server.start
      ensure
        monitor_thread&.kill
      end

      private

      def build_server
        server = WEBrick::HTTPServer.new(
          Port: PORT,
          Logger: WEBrick::Log.new(File::NULL),
          AccessLog: []
        )

        queue = @queue
        received_at = method(:update_received_at)

        server.mount_proc("/v1/logs") do |req, res|
          body = JSON.parse(req.body)
          received_at.call
          extract_log_records(body).each do |record|
            queue << {source: "otlp", event: record}
          end
          res.status = 200
          res.body = "{}"
          res.content_type = "application/json"
        end

        server
      end

      def extract_log_records(body)
        body
          .fetch("resourceLogs", [])
          .flat_map { |r| r.fetch("scopeLogs", []) }
          .flat_map { |s| s.fetch("logRecords", []) }
      end

      def update_received_at
        @last_received_at = Time.now
      end

      def start_no_data_monitor
        Thread.new do
          sleep NO_DATA_TIMEOUT
          if @last_received_at.nil?
            warn ""
            warn "  [otlp] no data received after #{NO_DATA_TIMEOUT}s — is Claude Code sending telemetry?"
            warn "  Set these env vars before starting claude:"
            warn "    export CLAUDE_CODE_ENABLE_TELEMETRY=1"
            warn "    export OTEL_LOGS_EXPORTER=otlp"
            warn "    export OTEL_EXPORTER_OTLP_PROTOCOL=http/json"
            warn "    export OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://localhost:#{PORT}/v1/logs"
            warn "    export OTEL_LOGS_EXPORT_INTERVAL=1000"
          end
        end
      end
    end
  end
end
