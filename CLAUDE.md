# Ruby Setup

Activate RVM before any commands: `source ~/.rvm/scripts/rvm && rvm use 3.4.1`

# Commands

- Install deps: `bundle install`
- Tests: `bundle exec rspec`
- Lint: `bundle exec standardrb --fix`

# Architecture

- New CLI commands go in `lib/token_lens/commands/` as a class
- Register them in `lib/token_lens/cli.rb` via Thor `desc` + method
- Tests mirror lib structure: `lib/token_lens/foo.rb` → `spec/token_lens/foo_spec.rb`
