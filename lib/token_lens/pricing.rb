# frozen_string_literal: true

module TokenLens
  module Pricing
    # Prices in USD per million tokens. Source: platform.claude.com/docs/en/about-claude/pricing
    # Last verified: 2026-03-23
    #
    # cache_creation = 5-minute cache write (1.25x input). The API reports this as
    # cache_creation_input_tokens in the usage object.
    # cache_read    = cache hit (0.1x input).
    #
    # Entries are matched via String#start_with? in order — put more specific prefixes first.
    TABLE = {
      # --- Opus 4.5 / 4.6 (new pricing tier: $5/$25) ---
      "claude-opus-4-6" => {input: 5.0, cache_read: 0.50, cache_creation: 6.25, output: 25.0},
      "claude-opus-4-5" => {input: 5.0, cache_read: 0.50, cache_creation: 6.25, output: 25.0},

      # --- Opus 4.0 / 4.1 (original tier: $15/$75) ---
      "claude-opus-4" => {input: 15.0, cache_read: 1.50, cache_creation: 18.75, output: 75.0},

      # --- Sonnet 4.x (all variants same price) ---
      "claude-sonnet-4" => {input: 3.0, cache_read: 0.30, cache_creation: 3.75, output: 15.0},

      # --- Haiku 4.5 ---
      "claude-haiku-4-5" => {input: 1.0, cache_read: 0.10, cache_creation: 1.25, output: 5.0},

      # --- Haiku 4.x fallback ---
      "claude-haiku-4" => {input: 1.0, cache_read: 0.10, cache_creation: 1.25, output: 5.0},

      # --- Claude 3.x (legacy, new-style IDs like claude-sonnet-3-7) ---
      "claude-sonnet-3" => {input: 3.0, cache_read: 0.30, cache_creation: 3.75, output: 15.0},
      "claude-haiku-3-5" => {input: 0.80, cache_read: 0.08, cache_creation: 1.00, output: 4.0},

      # --- Claude 3.x (old-style IDs like claude-3-opus-20240229) ---
      "claude-3-opus" => {input: 15.0, cache_read: 1.50, cache_creation: 18.75, output: 75.0},
      "claude-3-5-sonnet" => {input: 3.0, cache_read: 0.30, cache_creation: 3.75, output: 15.0},
      "claude-3-sonnet" => {input: 3.0, cache_read: 0.30, cache_creation: 3.75, output: 15.0},
      "claude-3-5-haiku" => {input: 0.80, cache_read: 0.08, cache_creation: 1.00, output: 4.0},
      "claude-3-haiku" => {input: 0.25, cache_read: 0.03, cache_creation: 0.30, output: 1.25}
    }.freeze

    # Fallback when model string is nil or unrecognised — use Sonnet 4 rates
    FALLBACK = {input: 3.0, cache_read: 0.30, cache_creation: 3.75, output: 15.0}.freeze

    def self.for_model(model)
      return FALLBACK unless model
      _prefix, rates = TABLE.find { |prefix, _| model.start_with?(prefix) }
      rates || FALLBACK
    end
  end
end
