# frozen_string_literal: true

require "spec_helper"
require "token_lens/pricing"

RSpec.describe TokenLens::Pricing do
  describe ".for_model" do
    it "returns opus-4-6 rates for claude-opus-4-6 models" do
      rates = described_class.for_model("claude-opus-4-6")
      expect(rates[:input]).to eq(5.0)
      expect(rates[:output]).to eq(25.0)
    end

    it "returns opus-4-0 rates for claude-opus-4-0 models" do
      rates = described_class.for_model("claude-opus-4-20250514")
      expect(rates[:input]).to eq(15.0)
      expect(rates[:output]).to eq(75.0)
    end

    it "returns sonnet rates for claude-sonnet-4 models" do
      rates = described_class.for_model("claude-sonnet-4-6")
      expect(rates[:input]).to eq(3.0)
      expect(rates[:cache_read]).to eq(0.30)
    end

    it "returns haiku-4-5 rates for claude-haiku-4-5 models" do
      rates = described_class.for_model("claude-haiku-4-5-20251001")
      expect(rates[:input]).to eq(1.0)
      expect(rates[:output]).to eq(5.0)
    end

    it "returns fallback rates for unknown models" do
      rates = described_class.for_model("claude-unknown-model")
      expect(rates).to eq(TokenLens::Pricing::FALLBACK)
    end

    it "returns fallback rates when model is nil" do
      rates = described_class.for_model(nil)
      expect(rates).to eq(TokenLens::Pricing::FALLBACK)
    end
  end
end
