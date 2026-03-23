# frozen_string_literal: true

require_relative "lib/token_lens/version"

Gem::Specification.new do |spec|
  spec.name = "token-lens"
  spec.version = TokenLens::VERSION
  spec.authors = ["rob durst"]
  spec.email = ["me@robdurst.com"]
  spec.summary = "Flame graphs for Claude Code token usage"
  spec.homepage = "https://github.com/BrickellResearch/token-lens"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.executables = ["token-lens"]
  spec.files = Dir.glob("lib/**/*") + Dir.glob("bin/**/*") + %w[LICENSE README.md]

  spec.add_dependency "thor", "~> 1.3"
end
