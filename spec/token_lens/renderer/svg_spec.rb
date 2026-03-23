# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/svg"
require "token_lens/renderer/annotator"
require "token_lens/renderer/layout"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Svg do
  def node(input_tokens: 0, output_tokens: 0, role: "assistant", tool_name: nil, children: [])
    content = tool_name ? [{"type" => "tool_use", "id" => "t1", "name" => tool_name}] : []
    token = TokenLens::Tokens::Jsonl.new(
      uuid: "test-uuid", parent_uuid: nil, type: "assistant",
      role: role, content: content, input_tokens: input_tokens,
      output_tokens: output_tokens, cache_read_tokens: 0, cache_creation_tokens: 0
    )
    {token: token, children: children}
  end

  def render_tree(tree)
    TokenLens::Renderer::Annotator.new.annotate(tree)
    TokenLens::Renderer::Layout.new.layout(tree)
    described_class.new.render(tree)
  end

  subject(:svg) { render_tree([node(input_tokens: 500, output_tokens: 100)]) }

  it "produces valid SVG envelope" do
    expect(svg).to start_with("<svg")
    expect(svg).to end_with("</svg>")
  end

  it "contains a rect for each node" do
    tree = [node(input_tokens: 100, children: [node(input_tokens: 50)])]
    result = render_tree(tree)
    expect(result.scan("<rect").length).to eq(3) # background + 2 nodes
  end

  it "uses assistant color for assistant nodes" do
    expect(svg).to include(TokenLens::Renderer::Svg::COLORS[:assistant])
  end

  it "uses tool color for assistant nodes with tool uses" do
    result = render_tree([node(input_tokens: 500, tool_name: "Bash")])
    expect(result).to include(TokenLens::Renderer::Svg::COLORS[:assistant_tool])
  end

  it "uses user color for user nodes" do
    result = render_tree([node(role: "user")])
    expect(result).to include(TokenLens::Renderer::Svg::COLORS[:user])
  end

  it "omits text for narrow nodes" do
    # two nodes where one will be very narrow
    wide = node(input_tokens: 10_000)
    narrow = node(input_tokens: 1)
    result = render_tree([wide, narrow])
    text_count = result.scan("<text").length
    expect(text_count).to be < 3
  end

  it "labels tool nodes with the tool name" do
    result = render_tree([node(input_tokens: 500, tool_name: "Read")])
    expect(result).to include("Read")
  end
end
