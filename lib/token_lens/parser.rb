# frozen_string_literal: true

require "json"
require "token_lens/tokens/jsonl"

module TokenLens
  class ParseError < StandardError; end

  class Parser
    def initialize(file_path:)
      @file_path = file_path
    end

    def parse
      raw_events = JSON.parse(read_file).map { |e| e["event"] }
      tokens = raw_events
        .map { |e| Tokens::Jsonl.from_raw(e) }
        .select { |t| t.type == "user" || t.type == "assistant" }
      tree = build_tree(tokens, raw_events)
      attach_subagent_turns(tree, raw_events)
      attach_task_notifications(tree)
      tree
    end

    private

    def build_tree(tokens, raw_events = [])
      index = tokens.each_with_object({}) { |t, h| h[t.uuid] = {token: t, children: []} }

      # Build a parent map covering ALL raw events (including filtered progress/tool-result
      # events) so we can walk through gaps when a token's direct parent was filtered out.
      raw_parent = {}
      raw_events.each { |e| raw_parent[e["uuid"]] = e["parentUuid"] if e["uuid"] }

      roots = []
      index.each_value do |node|
        parent_uuid = node[:token].parent_uuid
        # Walk up through filtered events to find the nearest indexed ancestor.
        hops = 0
        while parent_uuid && !index[parent_uuid] && hops < 20
          parent_uuid = raw_parent[parent_uuid]
          hops += 1
        end
        parent = parent_uuid && index[parent_uuid]
        parent ? parent[:children] << node : roots << node
      end

      roots
    end

    # Extract subagent turns from agent_progress events and attach them as
    # is_sidechain children of the assistant turn that invoked the Agent tool.
    def attach_subagent_turns(tree, raw_events)
      progress_by_tool_use = Hash.new { |h, k| h[k] = [] }
      raw_events.each do |evt|
        next unless evt["type"] == "progress"
        next unless evt.dig("data", "type") == "agent_progress"
        next unless evt.dig("data", "message", "type") == "assistant"
        tool_use_id = evt["parentToolUseID"]
        next unless tool_use_id
        progress_by_tool_use[tool_use_id] << evt
      end

      return if progress_by_tool_use.empty?

      # Index all nodes by their tool_use content IDs
      tool_use_node = {}
      flatten_nodes(tree).each do |node|
        node[:token].tool_uses.each { |tu| tool_use_node[tu["id"]] = node }
      end

      progress_by_tool_use.each do |tool_use_id, evts|
        parent = tool_use_node[tool_use_id]
        next unless parent
        parent[:children] += build_subagent_nodes(evts)
      end
    end

    # Collapse streaming chains (same requestId = one API call) and build tokens.
    def build_subagent_nodes(events)
      by_request = Hash.new { |h, k| h[k] = [] }
      events.each do |evt|
        req_id = evt.dig("data", "message", "requestId") || evt["uuid"]
        by_request[req_id] << evt
      end

      by_request.values
        .sort_by { |g| g.first["timestamp"] || "" }
        .map { |group| subagent_token(group) }
        .map { |t| {token: t, children: []} }
    end

    def subagent_token(group)
      representative = group.first
      msg_data = representative.dig("data", "message")
      inner = msg_data["message"] || {}
      usage = inner["usage"] || {}

      # Combine tool_uses across streaming events in this API call (parallel tools)
      combined_tool_uses = group.flat_map { |evt|
        Array(evt.dig("data", "message", "message", "content"))
          .select { |b| b.is_a?(Hash) && b["type"] == "tool_use" }
      }.uniq { |tu| tu["id"] }

      content = combined_tool_uses.empty? ? Array(inner["content"]) : combined_tool_uses

      Tokens::Jsonl.new(
        uuid: msg_data["uuid"] || representative["uuid"],
        parent_uuid: nil,
        request_id: msg_data["requestId"],
        type: "assistant",
        role: "assistant",
        model: inner["model"],
        is_sidechain: true,
        agent_id: representative.dig("data", "agentId"),
        content: content,
        input_tokens: usage["input_tokens"].to_i,
        output_tokens: usage["output_tokens"].to_i,
        cache_read_tokens: usage["cache_read_input_tokens"].to_i,
        cache_creation_tokens: usage["cache_creation_input_tokens"].to_i,
        marginal_input_tokens: 0,
        timestamp: representative["timestamp"],
        is_compaction: false
      )
    end

    # Wire task-notification user turns back to the Agent call that spawned them.
    # Each <task-notification> contains a <tool-use-id> that matches an Agent
    # tool call in the main thread. We detach the notification from its current
    # tree position, mark it is_sidechain, and attach it under the Agent call node.
    def attach_task_notifications(tree)
      all = flatten_nodes(tree)

      agent_node_by_tool_use = {}
      all.each do |node|
        node[:token].tool_uses.each do |tu|
          next unless tu["name"] == "Agent"
          agent_node_by_tool_use[tu["id"]] = node
        end
      end
      return if agent_node_by_tool_use.empty?

      all.select { |n| n[:token].is_task_notification? }.each do |node|
        tool_use_id = node[:token].human_text
          .match(/<tool-use-id>\s*(.*?)\s*<\/tool-use-id>/m)&.[](1)
        next unless tool_use_id
        agent_node = agent_node_by_tool_use[tool_use_id]
        next unless agent_node
        next unless remove_node(tree, node)

        node[:token] = node[:token].with(is_sidechain: true)
        agent_node[:children] << node
      end
    end

    def remove_node(nodes, target)
      return true if nodes.delete(target)
      nodes.any? { |node| remove_node(node[:children], target) }
    end

    def flatten_nodes(nodes)
      nodes.flat_map { |n| [n, *flatten_nodes(n[:children])] }
    end

    def read_file
      File.read(@file_path)
    rescue => e
      raise TokenLens::ParseError, "Failed to read file: #{e.message}"
    end
  end
end
