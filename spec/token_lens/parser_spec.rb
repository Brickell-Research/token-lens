# frozen_string_literal: true

require "spec_helper"
require "token_lens/parser"

RSpec.describe TokenLens::Parser do
  let(:fixture_path) { File.expand_path("../../fixtures/capture.json", __FILE__) }

  subject(:result) { described_class.new(file_path: fixture_path).parse }

  it "splits into jsonl and otlp buckets" do
    expect(result[:jsonl].length).to eq(2)
    expect(result[:otlp].length).to eq(1)
  end

  describe "jsonl tokens" do
    let(:assistant) { result[:jsonl].find(&:assistant?) }
    let(:user) { result[:jsonl].reject(&:assistant?).first }

    it "parses the user message" do
      expect(user.uuid).to eq("msg-001")
      expect(user.parent_uuid).to be_nil
    end

    it "parses the assistant message" do
      expect(assistant.uuid).to eq("msg-002")
      expect(assistant.parent_uuid).to eq("msg-001")
      expect(assistant.input_tokens).to eq(500)
      expect(assistant.output_tokens).to eq(120)
      expect(assistant.total_tokens).to eq(920)
    end

    it "extracts tool uses from the assistant message" do
      expect(assistant.tool_uses.length).to eq(1)
      expect(assistant.tool_uses.first["name"]).to eq("Bash")
    end
  end

  describe "otlp tokens" do
    let(:otlp) { result[:otlp].first }

    it "parses token counts" do
      expect(otlp.input_tokens).to eq(500)
      expect(otlp.output_tokens).to eq(120)
      expect(otlp.total_tokens).to eq(920)
    end

    it "parses model and trace info" do
      expect(otlp.model).to eq("claude-opus-4-6")
      expect(otlp.trace_id).to eq("trace-abc")
    end
  end
end
