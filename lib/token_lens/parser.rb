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
      events = JSON.parse(read_file)
      tokens = events
        .map { |e| Tokens::Jsonl.from_raw(e["event"]) }
        .select { |t| t.type == "user" || t.type == "assistant" }
      build_tree(tokens)
    end

    private

    def build_tree(tokens)
      index = tokens.each_with_object({}) { |t, h| h[t.uuid] = {token: t, children: []} }

      roots = []
      index.each_value do |node|
        parent = node[:token].parent_uuid && index[node[:token].parent_uuid]
        parent ? parent[:children] << node : roots << node
      end

      roots
    end

    def read_file
      File.read(@file_path)
    rescue => e
      raise TokenLens::ParseError, "Failed to read file: #{e.message}"
    end
  end
end
