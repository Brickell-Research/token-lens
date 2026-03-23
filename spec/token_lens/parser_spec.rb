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
    let(:agent_node) { root[:children].first }

    it "is an independent root" do
      expect(root[:token].uuid).to eq("msg-007")
      expect(root[:token].parent_uuid).to be_nil
    end

    it "has one assistant child that calls Agent" do
      expect(agent_node[:token].uuid).to eq("msg-008")
      expect(agent_node[:token].tool_uses.first["name"]).to eq("Agent")
    end

    it "attaches two subagent turns as sidechain children of the Agent call" do
      subagent = agent_node[:children].select { |c| c[:token].is_sidechain }
      expect(subagent.length).to eq(2)
    end

    it "subagent turns use haiku model and carry token counts" do
      subagent = agent_node[:children].select { |c| c[:token].is_sidechain }
      expect(subagent.map { |n| n[:token].model }.uniq).to eq(["claude-haiku-4-5-20251001"])
      expect(subagent.first[:token].cache_creation_tokens).to eq(800)
    end
  end

  describe "subagent (Agent tool) progress event handling" do
    let(:agent_fixture) { File.expand_path("../../fixtures/capture_agent.json", __FILE__) }
    subject(:agent_tree) { described_class.new(file_path: agent_fixture).parse }

    let(:outer_assistant) { agent_tree.first[:children].first }

    it "attaches subagent turns as sidechain children of the Agent call" do
      subagent_children = outer_assistant[:children].select { |c| c[:token].is_sidechain }
      expect(subagent_children).not_to be_empty
    end

    it "collapses streaming chain (same requestId) into one node with combined tool_uses" do
      subagent_children = outer_assistant[:children].select { |c| c[:token].is_sidechain }
      # prog-002 and prog-003 share req-sub-001; prog-004 is req-sub-002 → 2 nodes
      expect(subagent_children.length).to eq(2)
    end

    it "combines parallel tool_uses from the same API call" do
      subagent_children = outer_assistant[:children].select { |c| c[:token].is_sidechain }
      first_turn = subagent_children.first
      expect(first_turn[:token].tool_uses.map { |tu| tu["name"] }).to eq(%w[WebSearch WebSearch])
    end

    it "sets subagent model from the progress event" do
      subagent_children = outer_assistant[:children].select { |c| c[:token].is_sidechain }
      expect(subagent_children.first[:token].model).to eq("claude-haiku-4-5-20251001")
    end

    it "carries token counts from subagent usage" do
      subagent_children = outer_assistant[:children].select { |c| c[:token].is_sidechain }
      first = subagent_children.first
      expect(first[:token].input_tokens).to eq(100)
      expect(first[:token].output_tokens).to eq(20)
      expect(first[:token].cache_creation_tokens).to eq(500)
    end

    it "skips user-type progress events (tool results, prompts)" do
      all_sidechain = outer_assistant[:children].select { |c| c[:token].is_sidechain }
      expect(all_sidechain.all? { |n| n[:token].role == "assistant" }).to be true
    end
  end
end
