# frozen_string_literal: true

require "spec_helper"
require "token_lens/renderer/reshaper"
require "token_lens/tokens/jsonl"

RSpec.describe TokenLens::Renderer::Reshaper do
  def token(role:, input: 0, output: 0, cache_creation: 0, is_sidechain: false, text: nil, tool_result: false)
    content = if text
      [{"type" => "text", "text" => text}]
    elsif tool_result
      [{"type" => "tool_result", "tool_use_id" => "t1"}]
    else
      []
    end
    TokenLens::Tokens::Jsonl.new(
      uuid: "uuid-#{rand(10_000)}", parent_uuid: nil, request_id: nil, type: role,
      role: role, model: nil, is_sidechain: is_sidechain, agent_id: nil, content: content,
      input_tokens: input, output_tokens: output,
      cache_read_tokens: 0, cache_creation_tokens: cache_creation,
      marginal_input_tokens: 0,
      timestamp: nil, is_compaction: false
    )
  end

  def node(tok, children: [])
    {token: tok, children: children}
  end

  subject(:reshaper) { described_class.new }

  describe "human prompt re-rooting" do
    it "makes human prompt a root with assistant turns as siblings" do
      # user → assistant_1 → user(tool_result) → assistant_2
      a2 = node(token(role: "assistant", input: 200, output: 50))
      tool_result = node(token(role: "user", tool_result: true), children: [a2])
      a1 = node(token(role: "assistant", input: 100, output: 30), children: [tool_result])
      prompt = node(token(role: "user", text: "do something"), children: [a1])

      result = reshaper.reshape([prompt])

      expect(result.length).to eq(1)
      expect(result.first[:token].is_human_prompt?).to be true
      expect(result.first[:children].length).to eq(2)
      expect(result.first[:children].map { |c| c[:token].role }).to eq(%w[assistant assistant])
    end

    it "computes marginal_input_tokens as delta from previous turn" do
      a2 = node(token(role: "assistant", input: 300, output: 50))
      tool_result = node(token(role: "user", tool_result: true), children: [a2])
      a1 = node(token(role: "assistant", input: 100, output: 30), children: [tool_result])
      prompt = node(token(role: "user", text: "go"), children: [a1])

      result = reshaper.reshape([prompt])
      siblings = result.first[:children]

      expect(siblings[0][:token].marginal_input_tokens).to eq(100) # 100 - 0
      expect(siblings[1][:token].marginal_input_tokens).to eq(200) # 300 - 100
    end

    it "hoists nested human prompts to separate top-level roots" do
      a2 = node(token(role: "assistant", input: 200))
      p2 = node(token(role: "user", text: "follow-up"), children: [a2])
      a1 = node(token(role: "assistant", input: 100), children: [p2])
      p1 = node(token(role: "user", text: "initial"), children: [a1])

      result = reshaper.reshape([p1])

      expect(result.length).to eq(2)
      expect(result[0][:token].human_text).to eq("initial")
      expect(result[0][:children].map { |c| c[:token].role }).to eq(["assistant"])
      expect(result[1][:token].human_text).to eq("follow-up")
      expect(result[1][:children].map { |c| c[:token].role }).to eq(["assistant"])
    end

    it "preserves multiple human prompt roots as separate groups" do
      a1 = node(token(role: "assistant", input: 100))
      a2 = node(token(role: "assistant", input: 200))
      p1 = node(token(role: "user", text: "prompt one"), children: [a1])
      p2 = node(token(role: "user", text: "prompt two"), children: [a2])

      result = reshaper.reshape([p1, p2])

      expect(result.length).to eq(2)
      expect(result.map { |r| r[:token].human_text }).to eq(["prompt one", "prompt two"])
    end
  end

  describe "streaming chain collapse" do
    it "collapses thinking→text→tool_use chains with identical input usage" do
      tool_use = node(token(role: "assistant", input: 100, output: 500, cache_creation: 200))
      text = node(token(role: "assistant", input: 100, output: 8, cache_creation: 200), children: [tool_use])
      thinking = node(token(role: "assistant", input: 100, output: 8, cache_creation: 200), children: [text])
      prompt = node(token(role: "user", text: "go"), children: [thinking])

      result = reshaper.reshape([prompt])
      siblings = result.first[:children]

      expect(siblings.length).to eq(1)
      expect(siblings.first[:token].output_tokens).to eq(500)
    end
  end

  describe "sidechain handling" do
    it "keeps sidechain nodes nested under the spawning assistant turn" do
      sidechain = node(token(role: "assistant", input: 50, is_sidechain: true))
      a1 = node(token(role: "assistant", input: 100), children: [sidechain])
      prompt = node(token(role: "user", text: "go"), children: [a1])

      result = reshaper.reshape([prompt])
      assistant = result.first[:children].first

      expect(assistant[:children].length).to eq(1)
      expect(assistant[:children].first[:token].is_sidechain).to be true
    end
  end
end
