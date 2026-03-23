# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/layout"
require "token_lens/renderer/annotator"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Layout do
  def node(input_tokens: 0, output_tokens: 0, role: "assistant", children: [])
    token = TokenLens::Tokens::Jsonl.new(
      uuid: "test-uuid", parent_uuid: nil, type: "assistant",
      role: role, model: nil, is_sidechain: false, content: [], input_tokens: input_tokens,
      output_tokens: output_tokens, cache_read_tokens: 0, cache_creation_tokens: 0
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

  it "sets y based on depth" do
    child = node(input_tokens: 100)
    tree = [node(input_tokens: 200, children: [child])]
    annotate_and_layout(tree)
    expect(tree.first[:y]).to eq(0)
    expect(child[:y]).to eq(TokenLens::Renderer::Layout::ROW_HEIGHT)
  end
end
