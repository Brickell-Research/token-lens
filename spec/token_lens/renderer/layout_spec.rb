# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/layout"
require "token_lens/renderer/annotator"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Layout do
  def node(input_tokens: 0, output_tokens: 0, role: "assistant", children: [])
    token = TokenLens::Tokens::Jsonl.new(
      uuid: "test-uuid", parent_uuid: nil, request_id: nil, type: "assistant",
      role: role, model: nil, is_sidechain: false, agent_id: nil, content: [], input_tokens: input_tokens,
      output_tokens: output_tokens, cache_read_tokens: 0, cache_creation_tokens: 0,
      marginal_input_tokens: input_tokens,
      timestamp: nil, is_compaction: false
    )
    {token: token, children: children}
  end

  def annotate_and_layout(tree, canvas_width: 1200)
    TokenLens::Renderer::Annotator.new.annotate(tree)
    described_class.new(canvas_width: canvas_width).layout(tree)
  end

  it "single root spans the full canvas width" do
    tree = [node(input_tokens: 500)]
    annotate_and_layout(tree, canvas_width: 1200)
    expect(tree.first[:x]).to eq(0)
    expect(tree.first[:w]).to eq(1200)
  end

  it "two equal roots each get half the canvas" do
    tree = [node(input_tokens: 100), node(input_tokens: 100)]
    annotate_and_layout(tree, canvas_width: 1000)
    expect(tree[0][:x]).to eq(0)
    expect(tree[0][:w]).to eq(500)
    expect(tree[1][:x]).to eq(500)
    expect(tree[1][:w]).to eq(500)
  end

  it "child starts at parent x" do
    child = node(input_tokens: 100)
    tree = [node(input_tokens: 200, children: [child])]
    annotate_and_layout(tree)
    expect(child[:x]).to eq(tree.first[:x])
  end

  it "sets y based on depth (bottom-up: roots at bottom, children above)" do
    child = node(input_tokens: 100)
    tree = [node(input_tokens: 200, children: [child])]
    annotate_and_layout(tree)
    # max_depth=1: root (depth=0) is at y=ROW_HEIGHT, child (depth=1) at y=0
    expect(tree.first[:y]).to eq(TokenLens::Renderer::Layout::ROW_HEIGHT)
    expect(child[:y]).to eq(0)
  end

  describe "cost layout" do
    it "sets cost_x and cost_w on nodes" do
      tree = [node(input_tokens: 500, output_tokens: 100)]
      annotate_and_layout(tree, canvas_width: 1200)
      expect(tree.first[:cost_x]).to eq(0)
      expect(tree.first[:cost_w]).to eq(1200)
    end

    it "allocates cost_w proportional to subtree_cost" do
      # With fallback pricing, output tokens cost 5x input tokens.
      # node A: 0 input, 100 output → cost = 100 * 15 / 1M = 0.0015
      # node B: 0 input, 300 output → cost = 300 * 15 / 1M = 0.0045
      # ratio: A gets 1200 * 0.0015/0.006 = 300, B gets 900
      a = node(output_tokens: 100)
      b = node(output_tokens: 300)
      tree = [a, b]
      annotate_and_layout(tree, canvas_width: 1200)
      expect(a[:cost_w]).to eq(300)
      expect(b[:cost_w]).to eq(900)
    end

    it "child cost_x starts at parent cost_x" do
      child = node(output_tokens: 50)
      parent = node(output_tokens: 200, children: [child])
      annotate_and_layout([parent])
      expect(child[:cost_x]).to eq(parent[:cost_x])
    end
  end
end
