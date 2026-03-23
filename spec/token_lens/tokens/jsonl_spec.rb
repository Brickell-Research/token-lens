# frozen_string_literal: true

require "spec_helper"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Tokens::Jsonl do
  let(:raw) do
    {
      "uuid" => "abc-123",
      "parentUuid" => "parent-456",
      "type" => "assistant",
      "message" => {
        "role" => "assistant",
        "content" => [{"type" => "text", "text" => "hello"}],
        "usage" => {
          "input_tokens" => 100,
          "output_tokens" => 50,
          "cache_read_input_tokens" => 200,
          "cache_creation_input_tokens" => 10
        }
      }
    }
  end

  subject(:token) { described_class.from_raw(raw) }

  it "parses identifiers" do
    expect(token.uuid).to eq("abc-123")
    expect(token.parent_uuid).to eq("parent-456")
    expect(token.type).to eq("assistant")
    expect(token.role).to eq("assistant")
  end

  it "parses token counts" do
    expect(token.input_tokens).to eq(100)
    expect(token.output_tokens).to eq(50)
    expect(token.cache_read_tokens).to eq(200)
    expect(token.cache_creation_tokens).to eq(10)
  end

  it "computes total_tokens" do
    expect(token.total_tokens).to eq(360)
  end

  it "identifies assistant messages" do
    expect(token.assistant?).to be true
  end

  it "extracts tool_uses from content" do
    raw["message"]["content"] << {"type" => "tool_use", "id" => "t1", "name" => "Bash"}
    expect(token.tool_uses).to eq([{"type" => "tool_use", "id" => "t1", "name" => "Bash"}])
  end

  it "handles missing usage gracefully" do
    raw["message"].delete("usage")
    expect(token.input_tokens).to eq(0)
    expect(token.total_tokens).to eq(0)
  end
end
