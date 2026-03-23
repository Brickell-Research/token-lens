# frozen_string_literal: true

require_relative "../pricing"

module TokenLens
  module Tokens
    Jsonl = Data.define(
      :uuid,
      :parent_uuid,
      :request_id,
      :type,
      :role,
      :model,
      :is_sidechain,
      :agent_id,
      :content,
      :input_tokens,
      :output_tokens,
      :cache_read_tokens,
      :cache_creation_tokens,
      :marginal_input_tokens,
      :timestamp,
      :is_compaction
    ) do
      def self.from_raw(raw)
        msg = raw["message"] || {}
        usage = msg["usage"] || {}

        new(
          uuid: raw["uuid"],
          parent_uuid: raw["parentUuid"],
          request_id: raw["requestId"],
          type: raw["type"],
          role: msg["role"],
          model: msg["model"],
          is_sidechain: raw["isSidechain"] || false,
          agent_id: nil,
          content: Array(msg["content"]),
          input_tokens: usage["input_tokens"].to_i,
          output_tokens: usage["output_tokens"].to_i,
          cache_read_tokens: usage["cache_read_input_tokens"].to_i,
          cache_creation_tokens: usage["cache_creation_input_tokens"].to_i,
          marginal_input_tokens: 0,
          timestamp: raw["timestamp"],
          is_compaction: false
        )
      end

      def cost_usd
        p = Pricing.for_model(model)
        (marginal_input_tokens * p[:input] +
          cache_read_tokens * p[:cache_read] +
          cache_creation_tokens * p[:cache_creation] +
          output_tokens * p[:output]) / 1_000_000.0
      end

      def total_tokens
        input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens
      end

      def display_width
        marginal_input_tokens + cache_creation_tokens + output_tokens
      end

      def assistant?
        role == "assistant"
      end

      def is_human_prompt?
        return false unless role == "user"
        return false if tool_results.any?
        content.any? { |b| b.is_a?(String) || (b.is_a?(Hash) && b["type"] == "text") }
      end

      def is_task_notification?
        is_human_prompt? && human_text.start_with?("<task-notification>")
      end

      def task_notification_summary
        human_text.match(/<summary>(.*?)<\/summary>/m)&.[](1)&.strip
      end

      def human_text
        block = content.find { |b| b.is_a?(String) }
        return block if block
        block = content.find { |b| b.is_a?(Hash) && b["type"] == "text" }
        block&.dig("text") || ""
      end

      def tool_uses
        content.select { |b| b.is_a?(Hash) && b["type"] == "tool_use" }
      end

      def tool_results
        content.select { |b| b.is_a?(Hash) && b["type"] == "tool_result" }
      end
    end
  end
end
