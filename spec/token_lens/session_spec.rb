# frozen_string_literal: true

require "spec_helper"
require "token_lens/session"
require "tmpdir"

RSpec.describe TokenLens::Session do
  describe ".encoded_cwd" do
    it "replaces non-alphanumeric characters with hyphens, leaving alphanumeric characters unchanged" do
      expect(described_class.encoded_cwd("/Users/me/my-project")).to eq("-Users-me-my-project")
    end
  end

  describe ".active_jsonl" do
    it "raises when no session files exist" do
      expect do
        described_class.active_jsonl("/no/such/project")
      end.to raise_error(/No session files found/)
    end

    it "returns the most recently modified jsonl file" do
      Dir.mktmpdir do |tmpdir|
        older = File.join(tmpdir, "older.jsonl")
        newer = File.join(tmpdir, "newer.jsonl")

        File.write(older, "")
        sleep 0.01
        File.write(newer, "")

        encoded = File.basename(tmpdir)
        allow(described_class).to receive(:encoded_cwd).and_return(encoded)
        stub_const("TokenLens::Session::CLAUDE_DIR", Pathname.new(File.dirname(tmpdir)))

        result = described_class.active_jsonl("/fake/cwd")
        expect(result.basename.to_s).to eq("newer.jsonl")
      end
    end
  end
end
