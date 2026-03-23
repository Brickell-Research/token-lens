# frozen_string_literal: true

module TokenLens
  module Renderer
    class Reshaper
      def reshape(nodes)
        nodes = collapse_streaming(nodes)
        # Process roots iteratively so that human prompts discovered mid-thread
        # (nested inside an assistant chain) are hoisted to the top level rather
        # than stacked as children of the prompt that preceded them.
        @pending_roots = nodes.dup
        result = []
        while @pending_roots.any?
          batch = @pending_roots
          @pending_roots = []
          result += batch.flat_map { |node| process_root(node) }
        end
        result
      end

      private

      # Collapse streaming chains: thinking → text → tool_use events emitted by
      # Claude Code for a single API response, detected by identical input usage.
      def collapse_streaming(nodes)
        nodes.flat_map do |node|
          if streaming_intermediate?(node)
            collapse_streaming(node[:children])
          else
            node[:children] = collapse_streaming(node[:children])
            [node]
          end
        end
      end

      def streaming_intermediate?(node)
        return false unless node[:token].role == "assistant"
        return false unless node[:children].size == 1
        child = node[:children].first
        return false unless child[:token].role == "assistant"
        t, c = node[:token], child[:token]
        # Prefer request_id equality (same API call); fall back to token count fingerprint
        if t.request_id && c.request_id
          t.request_id == c.request_id
        else
          t.input_tokens == c.input_tokens &&
            t.cache_read_tokens == c.cache_read_tokens &&
            t.cache_creation_tokens == c.cache_creation_tokens
        end
      end

      # Re-root the tree around human prompt nodes. Human prompts become roots;
      # the linear assistant chain beneath them becomes a flat list of siblings.
      def process_root(node)
        t = node[:token]
        if t.is_human_prompt?
          siblings = flatten_thread(node[:children], prev_input: 0)
          [node.merge(children: siblings)]
        elsif t.role == "user"
          # Tool-result-only user at root level — hoist children
          node[:children].flat_map { |c| process_root(c) }
        else
          # Orphan assistant root (no human prompt ancestor)
          flatten_thread([node], prev_input: 0)
        end
      end

      # Flatten a linear user→assistant→user(tool_result)→assistant chain into
      # a flat list of assistant siblings, computing marginal_input_tokens deltas.
      # Sidechain children stay nested under the assistant that spawned them.
      #
      # through_assistant: tracks whether we've passed at least one assistant turn.
      # A human prompt encountered BEFORE any assistant (e.g. a screenshot attached
      # to the same user turn) is treated as transparent — we recurse into its
      # children rather than hoisting it. A human prompt encountered AFTER an
      # assistant is a genuine new conversational turn and gets hoisted.
      def flatten_thread(nodes, prev_input:, through_assistant: false)
        nodes.flat_map do |node|
          t = node[:token]
          if t.role == "user" && !t.is_human_prompt?
            flatten_thread(node[:children], prev_input: prev_input, through_assistant: through_assistant)
          elsif t.role == "assistant"
            marginal = [t.input_tokens - prev_input, 0].max
            compaction = prev_input > 0 && t.input_tokens < prev_input * 0.5
            sidechain = node[:children].select { |c| c[:token].is_sidechain }
            chain = node[:children].reject { |c| c[:token].is_sidechain }
            # Flatten the response chain inside task-notification sidechains so
            # they don't create arbitrarily deep linked-list nesting.
            sidechain = sidechain.map do |sc|
              sc[:token].is_task_notification? ? sc.merge(children: flatten_thread(sc[:children], prev_input: 0)) : sc
            end
            updated = node.merge(
              token: t.with(marginal_input_tokens: marginal, is_compaction: compaction),
              children: sidechain
            )
            [updated] + flatten_thread(chain, prev_input: t.input_tokens, through_assistant: true)
          elsif through_assistant
            # Human prompt after an assistant — genuine new turn, hoist to top level.
            @pending_roots << node
            []
          else
            # Human prompt before any assistant (consecutive user messages, e.g. an
            # image attachment). Treat as transparent and continue into its children.
            flatten_thread(node[:children], prev_input: prev_input, through_assistant: false)
          end
        end
      end
    end
  end
end
