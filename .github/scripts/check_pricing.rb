#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetches the Anthropic pricing docs page and compares prices against
# the current lib/token_lens/pricing.rb table.
#
# Exit codes:
#   0 — prices match
#   1 — differences found OR page could not be parsed (prints report to stdout)

require "net/http"
require "uri"

PRICING_URL = "https://platform.claude.com/docs/en/about-claude/pricing"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "token_lens/pricing"

# --------------------------------------------------------------------------
# Fetch (follows up to 5 redirects)
# --------------------------------------------------------------------------
def fetch(url_str, limit = 5)
  raise "Too many redirects fetching #{url_str}" if limit.zero?

  uri = URI(url_str)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
    open_timeout: 15, read_timeout: 30) do |http|
    http.get(uri.request_uri, "User-Agent" => "token-lens-pricing-check/1.0")
  end

  case response
  when Net::HTTPSuccess    then response.body
  when Net::HTTPRedirection then fetch(response["location"], limit - 1)
  else raise "HTTP #{response.code} fetching #{url_str}"
  end
end

# --------------------------------------------------------------------------
# Parse pricing table
#
# The docs page (platform.claude.com) is server-rendered and WebFetch returns
# clean markdown. We support both:
#   • Markdown table rows:  | Claude Opus 4.6 | $5 / MTok | ... |
#   • Plain HTML <tr>/<td> blocks (raw curl output)
#
# Columns: Model | Input | 5m Cache Write | 1h Cache Write | Cache Read | Output
# We keep: input, cache_creation (5m write), cache_read, output
# --------------------------------------------------------------------------
def strip_html(str)
  str.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
end

def parse_price(str)
  str.match(/\$([0-9.]+)\s*\/\s*MTok/)&.[](1)&.to_f
end

PIPE_ROW = /\|([^|]+)\|\s*\$([0-9.]+)[^|]*\|\s*\$([0-9.]+)[^|]*\|\s*\$([0-9.]+)[^|]*\|\s*\$([0-9.]+)[^|]*\|\s*\$([0-9.]+)[^|]*/

def parse_markdown_table(body)
  results = {}
  body.each_line do |line|
    m = line.match(PIPE_ROW)
    next unless m
    name = strip_html(m[1]).sub(/\(\s*deprecated[^)]*\)/i, "").strip
    next unless name.match?(/\AClaude /i)
    results[name] = {
      input: m[2].to_f,
      cache_creation: m[3].to_f,
      cache_read: m[5].to_f,
      output: m[6].to_f
    }
  end
  results
end

def parse_html_table(body)
  results = {}
  # Grab each <tr> block (multiline)
  body.scan(/<tr[^>]*>(.*?)<\/tr>/mi) do |row_html,|
    cells = row_html.scan(/<t[dh][^>]*>(.*?)<\/t[dh]>/mi).map { |c| strip_html(c.first) }
    next unless cells.length >= 6
    name = cells[0].sub(/\(\s*deprecated[^)]*\)/i, "").strip
    next unless name.match?(/\AClaude /i)
    prices = cells[1..5].map { |c| parse_price(c) }
    next if prices.any?(&:nil?)
    results[name] = {
      input: prices[0],
      cache_creation: prices[1],
      cache_read: prices[3],
      output: prices[4]
    }
  end
  results
end

# --------------------------------------------------------------------------
# Map display names from the docs page to pricing.rb prefix keys.
# This is intentionally explicit — we want humans to notice when a new
# model appears here that isn't mapped yet.
# --------------------------------------------------------------------------
NAME_TO_PREFIX = {
  "Claude Opus 4.6"   => "claude-opus-4-6",
  "Claude Opus 4.5"   => "claude-opus-4-5",
  "Claude Opus 4.1"   => "claude-opus-4-1",
  "Claude Opus 4"     => "claude-opus-4",
  "Claude Sonnet 4.6" => "claude-sonnet-4-6",
  "Claude Sonnet 4.5" => "claude-sonnet-4-5",
  "Claude Sonnet 4"   => "claude-sonnet-4",
  "Claude Sonnet 3.7" => "claude-sonnet-3",
  "Claude Haiku 4.5"  => "claude-haiku-4-5",
  "Claude Haiku 3.5"  => "claude-haiku-3-5",
  "Claude Opus 3"     => "claude-3-opus",
  "Claude Haiku 3"    => "claude-3-haiku"
}.freeze

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
begin
  body = fetch(PRICING_URL)

  live = parse_markdown_table(body)
  live = parse_html_table(body) if live.empty?

  if live.empty?
    puts "PARSE_FAILED"
    puts "Could not find a pricing table in the fetched page."
    puts "The page may be JS-rendered or its structure has changed."
    puts "Please check manually: #{PRICING_URL}"
    exit 1
  end

  current = TokenLens::Pricing::TABLE
  diffs = []
  new_models = []

  live.each do |display_name, live_rates|
    prefix = NAME_TO_PREFIX[display_name]
    if prefix.nil?
      new_models << display_name
      next
    end

    # Use the same prefix-matching lookup as the real code, not direct key access
    current_rates = TokenLens::Pricing.for_model(prefix)

    %i[input cache_creation cache_read output].each do |key|
      cur = current_rates[key]
      got = live_rates[key]
      next if cur == got
      diffs << "#{display_name} (#{prefix}) #{key}: $#{cur} → $#{got}"
    end
  end

  if diffs.empty? && new_models.empty?
    puts "OK: #{live.length} models checked, all prices match."
    exit 0
  end

  puts "DIFFERENCES FOUND\n\n"
  diffs.each { |d| puts "  • #{d}" }
  if new_models.any?
    puts "\n  New models on docs page not in NAME_TO_PREFIX mapping:"
    new_models.each { |n| puts "    - #{n}" }
  end
  puts "\nSource: #{PRICING_URL}"

  exit 1
rescue => e
  puts "ERROR: #{e.message}"
  exit 1
end
