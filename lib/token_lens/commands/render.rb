# frozen_string_literal: true

module TokenLens
  module Commands
    class Render
      def initialize(file_path:, output:)
        @file_path = file_path
        @output = output
      end

      def run
        warn "Rendering #{@file_path} → #{@output}..."
        # TODO: parse → build tree → emit SVG
        warn "Render not yet implemented"
      end
    end
  end
end
