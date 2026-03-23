# frozen_string_literal: true

module TokenLens
  module Tokens
    Jsonl = Data.define(
      :uuid,
      :parent_uuid,
      :type,
      :role,
      :model,
      :is_sidechain,
      :content,
      :input_tokens,
      :output_tokens,
      :cache_read_tokens,
      :cache_creation_tokens
    ) do
      def self.from_raw(raw)
        msg = raw["message"] || {}
        usage = msg["usage"] || {}

        new(
          uuid: raw["uuid"],
          parent_uuid: raw["parentUuid"],
          type: raw["type"],
          role: msg["role"],
          model: msg["model"],
          is_sidechain: raw["isSidechain"] || false,
          content: Array(msg["content"]),
          input_tokens: usage["input_tokens"].to_i,
          output_tokens: usage["output_tokens"].to_i,
          cache_read_tokens: usage["cache_read_input_tokens"].to_i,
          cache_creation_tokens: usage["cache_creation_input_tokens"].to_i
        )
      end

      def total_tokens
        input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens
      end

      def assistant?
        role == "assistant"
      end

      def tool_uses
        content.select { |b| b["type"] == "tool_use" }
      end

      def tool_results
        content.select { |b| b["type"] == "tool_result" }
      end
    end
  end
end
