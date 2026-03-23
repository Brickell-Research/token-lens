# frozen_string_literal: true

module TokenLens
  module Tokens
    Otlp = Data.define(
      :time_unix_nano,
      :severity_text,
      :body,
      :attributes,
      :trace_id,
      :span_id
    ) do
      def self.from_raw(raw)
        new(
          time_unix_nano: raw["timeUnixNano"].to_i,
          severity_text: raw["severityText"],
          body: raw.dig("body", "stringValue"),
          attributes: normalize_attributes(raw["attributes"] || []),
          trace_id: raw["traceId"],
          span_id: raw["spanId"]
        )
      end

      def self.normalize_attributes(attrs)
        attrs.each_with_object({}) do |kv, h|
          h[kv["key"]] = unwrap_value(kv["value"])
        end
      end

      def self.unwrap_value(v)
        return nil if v.nil?
        v["stringValue"] || v["intValue"]&.to_i || v["doubleValue"]&.to_f || v["boolValue"]
      end

      def input_tokens
        attributes["gen_ai.usage.input_tokens"].to_i
      end

      def output_tokens
        attributes["gen_ai.usage.output_tokens"].to_i
      end

      def cache_read_tokens
        attributes["gen_ai.usage.cache_read_input_tokens"].to_i
      end

      def cache_creation_tokens
        attributes["gen_ai.usage.cache_creation_input_tokens"].to_i
      end

      def total_tokens
        input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens
      end

      def model
        attributes["gen_ai.request.model"]
      end

      def timestamp
        time_unix_nano / 1_000_000_000.0
      end
    end
  end
end
