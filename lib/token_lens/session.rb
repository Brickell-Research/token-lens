# frozen_string_literal: true

require "json"
require "pathname"

module TokenLens
  module Session
    # Claude Code stores sessions at ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
    # where encoded-cwd is the absolute working directory with every non-alphanumeric
    # character replaced by a hyphen (e.g. /Users/me/proj => -Users-me-proj)
    CLAUDE_DIR = Pathname.new(File.expand_path("~/.claude/projects"))

    def self.encoded_cwd(dir = Dir.pwd)
      dir.gsub(/[^a-zA-Z0-9]/, "-")
    end

    def self.active_jsonl(dir = Dir.pwd)
      project_dir = CLAUDE_DIR / encoded_cwd(dir)
      jsonl_files = project_dir.glob("*.jsonl")
      raise "No session files found in #{project_dir}" if jsonl_files.empty?
      jsonl_files.max_by(&:mtime)
    end

    # Returns the most recently modified session file across ALL projects.
    def self.latest_jsonl
      all = CLAUDE_DIR.glob("*/*.jsonl")
      raise "No session files found in #{CLAUDE_DIR}" if all.empty?
      all.max_by(&:mtime)
    end

    # Like active_jsonl but falls back to latest_jsonl with a warning when
    # the current directory has no sessions (e.g. running from ~/Desktop).
    def self.active_or_latest_jsonl(dir = Dir.pwd)
      active_jsonl(dir)
    rescue RuntimeError
      path = latest_jsonl
      warn "  [session] no sessions for #{dir}, using most recent: #{path}"
      path
    end

    def self.tail(path, &block)
      last_pos = File.size(path)
      loop do
        sleep 0.1
        current_size = File.size(path)
        # if file size hasn't changed, skip
        next if current_size == last_pos

        # otherwise, read new lines from the file
        File.open(path) do |f|
          f.seek(last_pos)
          f.each_line { |line| block.call(JSON.parse(line)) }
          last_pos = f.pos
        end
      end
    end
  end
end
