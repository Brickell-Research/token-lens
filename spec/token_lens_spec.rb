require "spec_helper"

RSpec.describe TokenLens do
  it "has a version" do
    expect(TokenLens::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  it "greets" do
    expect(TokenLens.hello).to start_with("token-lens v")
  end
end
