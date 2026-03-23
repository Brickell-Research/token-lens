# frozen_string_literal: true

require "json"
require "token_lens/parser"

module TokenLens
  module Commands
    class Parse
      def initialize(file_path:)
        @file_path = file_path
      end

      def run
        warn "Parsing #{@file_path}..."
        ::TokenLens::Parser.new(file_path: @file_path).parse
      end
    end
  end
end
