# frozen_string_literal: true

require_relative "token_lens/version"

module TokenLens
  def self.hello
    "token-lens v#{VERSION}"
  end
end
