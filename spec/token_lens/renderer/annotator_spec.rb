# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/annotator"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Annotator do
  def node(input_tokens: 0, output_tokens: 0, role: "assistant", children: [])
    token = TokenLens::Tokens::Jsonl.new(
      uuid: "test-uuid", parent_uuid: nil, type: "assistant",
      role: role, content: [], input_tokens: input_tokens,
      output_tokens: output_tokens, cache_read_tokens: 0, cache_creation_tokens: 0
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
end
