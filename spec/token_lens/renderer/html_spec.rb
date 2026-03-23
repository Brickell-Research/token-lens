# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/html"
require "token_lens/renderer/annotator"
require "token_lens/renderer/layout"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Html do
  def node(input_tokens: 0, output_tokens: 0, role: "assistant", tool_name: nil,
    text: nil, children: [])
    content = if tool_name
      [{"type" => "tool_use", "id" => "t1", "name" => tool_name}]
    elsif text
      [{"type" => "text", "text" => text}]
    else
      []
    end
    token = TokenLens::Tokens::Jsonl.new(
      uuid: "test-uuid", parent_uuid: nil, request_id: nil, type: role,
      role: role, model: nil, is_sidechain: false, agent_id: nil, content: content,
      input_tokens: input_tokens, output_tokens: output_tokens,
      cache_read_tokens: 0, cache_creation_tokens: 0,
      marginal_input_tokens: input_tokens,
      timestamp: nil, is_compaction: false
    )
    {token: token, children: children}
  end

  def render_tree(tree)
    TokenLens::Renderer::Annotator.new.annotate(tree)
    TokenLens::Renderer::Layout.new.layout(tree)
    described_class.new.render(tree)
  end

  subject(:html) { render_tree([node(input_tokens: 500, output_tokens: 100)]) }

  it "produces a valid HTML document" do
    expect(html).to include("<!DOCTYPE html>")
    expect(html).to include("</html>")
  end

  it "contains a bar div for each node" do
    tree = [node(input_tokens: 100, children: [node(input_tokens: 50)])]
    result = render_tree(tree)
    expect(result.scan('class="bar bar-c-').length).to eq(2)
  end

  it "uses assistant color class for assistant nodes" do
    expect(html).to include("bar-c-assistant")
  end

  it "uses tool color class for assistant nodes with tool uses" do
    result = render_tree([node(input_tokens: 500, tool_name: "Bash")])
    expect(result).to include("bar-c-tool")
  end

  it "labels human prompt nodes with their text" do
    result = render_tree([node(role: "user", text: "How does this work?", input_tokens: 500)])
    expect(result).to include("How does this work?")
  end

  it "hides label for narrow bars" do
    wide = node(input_tokens: 975)
    narrow = node(input_tokens: 25)
    result = render_tree([wide, narrow])
    expect(result).to include("display:none")
  end

  it "escapes HTML special chars in labels and tooltips" do
    result = render_tree([node(role: "user", text: "<script>alert('xss')</script>", input_tokens: 500)])
    expect(result).not_to include("<script>alert")
    expect(result).to include("&lt;script&gt;")
  end
end
