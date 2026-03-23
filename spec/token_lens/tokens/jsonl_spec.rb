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

  it "parses request_id" do
    raw["requestId"] = "req_abc123"
    expect(token.request_id).to eq("req_abc123")
  end

  it "defaults request_id to nil when absent" do
    expect(token.request_id).to be_nil
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

  it "defaults marginal_input_tokens to 0" do
    expect(token.marginal_input_tokens).to eq(0)
  end

  it "defaults agent_id to nil" do
    expect(token.agent_id).to be_nil
  end

  it "stores agent_id when set via with" do
    t = token.with(agent_id: "agent-123")
    expect(t.agent_id).to eq("agent-123")
  end

  it "computes display_width from marginal_input + cache_creation + output" do
    t = token.with(marginal_input_tokens: 50)
    expect(t.display_width).to eq(50 + 10 + 50) # marginal + cache_creation + output
  end

  describe "#cost_usd" do
    it "computes cost using marginal input, cache reads, cache creation, and output" do
      # model nil → fallback sonnet-4 rates: input $3, cache_read $0.30, cache_creation $3.75, output $15
      t = token.with(marginal_input_tokens: 1_000_000, cache_read_tokens: 0,
        cache_creation_tokens: 0, output_tokens: 0)
      expect(t.cost_usd).to be_within(0.000001).of(3.0)
    end

    it "uses model-specific pricing for opus-4-6" do
      t = token.with(model: "claude-opus-4-6", marginal_input_tokens: 1_000_000,
        cache_read_tokens: 0, cache_creation_tokens: 0, output_tokens: 0)
      expect(t.cost_usd).to be_within(0.000001).of(5.0)
    end

    it "uses model-specific pricing for haiku-4-5" do
      t = token.with(model: "claude-haiku-4-5-20251001", marginal_input_tokens: 1_000_000,
        cache_read_tokens: 0, cache_creation_tokens: 0, output_tokens: 0)
      expect(t.cost_usd).to be_within(0.000001).of(1.0)
    end

    it "returns 0 for a token with all zero counts" do
      t = token.with(marginal_input_tokens: 0, cache_read_tokens: 0,
        cache_creation_tokens: 0, output_tokens: 0)
      expect(t.cost_usd).to eq(0)
    end
  end

  describe "#is_human_prompt?" do
    it "is true for user text messages" do
      raw["type"] = "user"
      raw["message"]["role"] = "user"
      raw["message"]["content"] = [{"type" => "text", "text" => "hello"}]
      expect(token.is_human_prompt?).to be true
    end

    it "is false for user tool_result messages" do
      raw["type"] = "user"
      raw["message"]["role"] = "user"
      raw["message"]["content"] = [{"type" => "tool_result", "tool_use_id" => "t1"}]
      expect(token.is_human_prompt?).to be false
    end

    it "is false for assistant messages" do
      expect(token.is_human_prompt?).to be false
    end
  end

  describe "#human_text" do
    it "returns the text content of a human message" do
      raw["message"]["role"] = "user"
      raw["message"]["content"] = [{"type" => "text", "text" => "How does this work?"}]
      expect(token.human_text).to eq("How does this work?")
    end
  end
end
