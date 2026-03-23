# frozen_string_literal: true

require "spec_helper"
require "token_lens/tokens/otlp"

RSpec.describe TokenLens::Tokens::Otlp do
  let(:raw) do
    {
      "timeUnixNano" => "1711234567890000000",
      "severityText" => "INFO",
      "body" => {"stringValue" => "API request completed"},
      "traceId" => "abc123",
      "spanId" => "def456",
      "attributes" => [
        {"key" => "gen_ai.usage.input_tokens", "value" => {"intValue" => "1234"}},
        {"key" => "gen_ai.usage.output_tokens", "value" => {"intValue" => "456"}},
        {"key" => "gen_ai.usage.cache_read_input_tokens", "value" => {"intValue" => "800"}},
        {"key" => "gen_ai.usage.cache_creation_input_tokens", "value" => {"intValue" => "0"}},
        {"key" => "gen_ai.request.model", "value" => {"stringValue" => "claude-opus-4-5"}}
      ]
    }
  end

  subject(:token) { described_class.from_raw(raw) }

  it "parses metadata" do
    expect(token.severity_text).to eq("INFO")
    expect(token.body).to eq("API request completed")
    expect(token.trace_id).to eq("abc123")
    expect(token.span_id).to eq("def456")
  end

  it "parses token counts from attributes" do
    expect(token.input_tokens).to eq(1234)
    expect(token.output_tokens).to eq(456)
    expect(token.cache_read_tokens).to eq(800)
    expect(token.cache_creation_tokens).to eq(0)
  end

  it "computes total_tokens" do
    expect(token.total_tokens).to eq(2490)
  end

  it "exposes model" do
    expect(token.model).to eq("claude-opus-4-5")
  end

  it "converts time_unix_nano to a timestamp" do
    expect(token.timestamp).to be_within(0.001).of(1711234567.89)
  end

  it "handles missing attributes gracefully" do
    raw["attributes"] = []
    expect(token.input_tokens).to eq(0)
    expect(token.model).to be_nil
  end
end
