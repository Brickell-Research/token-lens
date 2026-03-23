# frozen_string_literal: true

require "spec_helper"
require "token_lens/parser"

RSpec.describe TokenLens::Parser do
  let(:fixture_path) { File.expand_path("../../fixtures/capture.json", __FILE__) }
  subject(:result) { described_class.new(file_path: fixture_path).parse }

  it "returns two jsonl roots and four otlp events" do
    expect(result[:jsonl].length).to eq(2)
    expect(result[:otlp].length).to eq(4)
  end

  describe "jsonl tree" do
    let(:first_root) { result[:jsonl].first }
    let(:second_root) { result[:jsonl].last }

    it "first root is the opening user message" do
      expect(first_root[:token].uuid).to eq("msg-001")
      expect(first_root[:token].parent_uuid).to be_nil
    end

    it "second root is an independent thread" do
      expect(second_root[:token].uuid).to eq("msg-007")
      expect(second_root[:token].parent_uuid).to be_nil
    end

    it "first thread is 6 nodes deep" do
      depth = ->(node) { node[:children].empty? ? 1 : 1 + node[:children].map { |c| depth.call(c) }.max }
      expect(depth.call(first_root)).to eq(6)
    end

    it "assistant nodes carry token counts" do
      assistant = first_root[:children].first
      expect(assistant[:token].input_tokens).to eq(800)
      expect(assistant[:token].output_tokens).to eq(150)
      expect(assistant[:token].cache_creation_tokens).to eq(400)
    end

    it "tool uses are linked to the right assistant node" do
      bash_node = first_root[:children].first
      read_node = first_root[:children].first[:children].first[:children].first
      expect(bash_node[:token].tool_uses.first["name"]).to eq("Bash")
      expect(read_node[:token].tool_uses.first["name"]).to eq("Read")
    end

    it "tool results appear in the following user nodes" do
      tool_result_node = first_root[:children].first[:children].first
      expect(tool_result_node[:token].tool_results.first["tool_use_id"]).to eq("tool-001")
    end

    it "leaf node has no children" do
      leaf = first_root[:children].first[:children].first[:children].first[:children].first[:children].first
      expect(leaf[:children]).to be_empty
    end
  end

  describe "otlp events" do
    it "all four events have a model set" do
      expect(result[:otlp].map(&:model).uniq).to eq(["claude-opus-4-6"])
    end

    it "events are in chronological order" do
      timestamps = result[:otlp].map(&:time_unix_nano)
      expect(timestamps).to eq(timestamps.sort)
    end

    it "total tokens across all otlp events" do
      total = result[:otlp].sum(&:total_tokens)
      expect(total).to eq(10_500)
    end
  end
end
