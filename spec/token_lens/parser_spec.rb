# frozen_string_literal: true

require "spec_helper"
require "token_lens/parser"

RSpec.describe TokenLens::Parser do
  let(:fixture_path) { File.expand_path("../../fixtures/capture.json", __FILE__) }
  subject(:tree) { described_class.new(file_path: fixture_path).parse }

  it "returns two root nodes" do
    expect(tree.length).to eq(2)
  end

  describe "first thread" do
    let(:root) { tree.first }

    it "root is the opening user message" do
      expect(root[:token].uuid).to eq("msg-001")
      expect(root[:token].parent_uuid).to be_nil
    end

    it "is 6 nodes deep" do
      depth = ->(node) { node[:children].empty? ? 1 : 1 + node[:children].map { |c| depth.call(c) }.max }
      expect(depth.call(root)).to eq(6)
    end

    it "assistant nodes carry token counts" do
      assistant = root[:children].first
      expect(assistant[:token].input_tokens).to eq(800)
      expect(assistant[:token].output_tokens).to eq(150)
      expect(assistant[:token].cache_creation_tokens).to eq(400)
    end

    it "tool uses are on the right nodes" do
      bash_node = root[:children].first
      read_node = bash_node[:children].first[:children].first
      expect(bash_node[:token].tool_uses.first["name"]).to eq("Bash")
      expect(read_node[:token].tool_uses.first["name"]).to eq("Read")
    end

    it "tool results reference the correct tool_use_id" do
      tool_result_node = root[:children].first[:children].first
      expect(tool_result_node[:token].tool_results.first["tool_use_id"]).to eq("tool-001")
    end

    it "leaf has no children" do
      leaf = root[:children].first[:children].first[:children].first[:children].first[:children].first
      expect(leaf[:children]).to be_empty
    end
  end

  describe "second thread" do
    let(:root) { tree.last }

    it "is an independent root" do
      expect(root[:token].uuid).to eq("msg-007")
      expect(root[:token].parent_uuid).to be_nil
    end

    it "has one assistant child with token counts" do
      child = root[:children].first
      expect(child[:token].uuid).to eq("msg-008")
      expect(child[:token].total_tokens).to eq(3000)
    end
  end
end
