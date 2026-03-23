require "json"
require "token_lens/tokens/jsonl"
require "token_lens/tokens/otlp"

module TokenLens
  class Parser
    def initialize(file_path:)
      @file_path = file_path
    end

    def parse
      tokens = split_by_type(JSON.parse(read_file))
      {
        jsonl: jsonl_tokens_tree(tokens[:jsonl]),
        otlp: tokens[:otlp]
      }
    end

    def jsonl_tokens_tree(jsonl_tokens)
      index = jsonl_tokens.each_with_object({}) { |t, h| h[t.uuid] = {token: t, children: []} }

      roots = []
      index.each_value do |node|
        parent = node[:token].parent_uuid && index[node[:token].parent_uuid]
        parent ? parent[:children] << node : roots << node
      end

      roots
    end

    def split_by_type(jsonified_contents)
      otlp = []
      jsonl = []

      jsonified_contents.each do |token|
        source = token["source"]
        if source == "otlp"
          otlp << Tokens::Otlp.from_raw(token["event"])
        elsif source == "jsonl"
          jsonl << Tokens::Jsonl.from_raw(token["event"])
        else
          warn "Unknown source: #{source}"
        end
      end

      { otlp: otlp, jsonl: jsonl }
    end

    private

    def read_file
      begin
        File.read(@file_path)
      rescue => e
        raise TokenLens::ParseError, "Failed to read file: #{e.message}"
      end
    end
  end
end
