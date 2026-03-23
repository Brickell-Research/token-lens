# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/annotator"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Annotator do
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

  subject(:annotator) { described_class.new }

  it "sets depth 0 on root nodes" do
    tree = [node(input_tokens: 100)]
    annotator.annotate(tree)
    expect(tree.first[:depth]).to eq(0)
  end

  it "sets depth 1 on children" do
    child = node(input_tokens: 50)
    tree = [node(input_tokens: 100, children: [child])]
    annotator.annotate(tree)
    expect(child[:depth]).to eq(1)
  end

  it "subtree_tokens for a leaf = own total_tokens" do
    tree = [node(input_tokens: 100, output_tokens: 50)]
    annotator.annotate(tree)
    expect(tree.first[:subtree_tokens]).to eq(150)
  end

  it "subtree_tokens for parent = own tokens + child subtree_tokens" do
    child = node(input_tokens: 200)
    tree = [node(input_tokens: 100, children: [child])]
    annotator.annotate(tree)
    expect(tree.first[:subtree_tokens]).to eq(300)
  end

  it "gives 0-token nodes a minimum subtree_tokens of 1" do
    tree = [node(role: "user")]
    annotator.annotate(tree)
    expect(tree.first[:subtree_tokens]).to eq(1)
  end

  describe "subtree_cost" do
    it "sets subtree_cost on a leaf node" do
      # fallback sonnet-4 rates: input $3/MTok, output $15/MTok
      # cost = (100 * 3.0 + 50 * 15.0) / 1_000_000 = 1050 / 1_000_000 = 0.00105
      tree = [node(input_tokens: 100, output_tokens: 50)]
      annotator.annotate(tree)
      expect(tree.first[:subtree_cost]).to be_within(0.0000001).of(0.00105)
    end

    it "rolls up subtree_cost through children" do
      child = node(input_tokens: 100, output_tokens: 50)
      parent = node(input_tokens: 200, output_tokens: 80, children: [child])
      annotator.annotate([parent])
      child_cost = child[:subtree_cost]
      parent_own_cost = parent[:token].cost_usd
      expect(parent[:subtree_cost]).to be_within(0.0000001).of(parent_own_cost + child_cost)
    end

    it "sets subtree_cost to 0 for zero-token user nodes" do
      tree = [node(role: "user")]
      annotator.annotate(tree)
      expect(tree.first[:subtree_cost]).to eq(0)
    end
  end
end
