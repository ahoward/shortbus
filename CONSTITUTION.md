# shortbus Code Constitution

This document defines the coding principles, style, and architectural patterns for shortbus development.

---

## Core Philosophy

> **Simple, self-contained, Ruby libs**

Inspired by `lib/s3.rb` and `lib/envkee.rb` - the goal is minimalist, readable, powerful code that does one thing well.

---

## Guiding Principles

### 1. **Simplicity Over Cleverness**
- Prefer clarity over brevity
- Code should be self-documenting
- No magic unless absolutely necessary
- POLS (Principle of Least Surprise)

### 2. **Self-Contained Modules**
- Each module is a complete unit
- Minimal dependencies
- `extend self` for module-level functionality
- Clean public API surface

### 3. **Git-Clone Install Philosophy**
- Everything contained in project directory
- No global state or system pollution
- Works from `git clone` + run
- Self-bootstrapping when possible

### 4. **Modern Ruby, Classic Style**
- Use modern Ruby features (3.2+):
  - Named parameters (`key:, value:`)
  - Hash shorthand (`{ key:, value: }`)
  - Pattern matching (where appropriate)
  - Ractors for parallelism (if needed)
- Classic patterns from samples:
  - Module structure (like `ro`)
  - Configuration objects
  - Method aliasing for convenience
  - Lazy initialization

---

## Code Structure Patterns

### Module Organization (from `ro`, `s3`, `envkee`)

```ruby
module Shortbus
  # Class-level state
  def config
    @config ||= Config.new
  end

  def config=(value)
    @config = value
  end

  # Public API methods
  def publish(topic, message, **opts)
    # Implementation
  end

  # Module-level access
  extend self
end
```

### Configuration (from `ro`)

```ruby
module Shortbus
  def env
    Map.for({
      root:     ENV['SHORTBUS_ROOT'],
      port:     ENV['SHORTBUS_PORT'],
      log:      ENV['SHORTBUS_LOG'],
      debug:    ENV['SHORTBUS_DEBUG'],
    })
  end

  def defaults
    Map.for({
      root:     './rendezvous',
      port:     8080,
      log:      nil,
      debug:    nil,
    })
  end

  def config
    @config ||= Config.new
  end

  extend self
end
```

### Dependency Loading (from `ro/_lib.rb`)

```ruby
module Shortbus
  class << self
    def libs
      %w[ socket fileutils pathname yaml json logger ]
    end

    def dependencies
      {
        'listen' => ['listen', '~> 3.8'],
        'map' => ['map', '~> 6.6'],
        # etc
      }
    end

    def libdir(*args)
      @libdir ||= File.dirname(File.expand_path(__FILE__))
      args.empty? ? @libdir : File.join(@libdir, *args)
    end

    def load(*libs)
      libs = libs.join(' ').scan(/[^\s+]+/)
      libdir { libs.each { |lib| Kernel.load(lib) } }
    end

    def load_dependencies!
      libs.each { |lib| require lib }

      dependencies.each do |lib, dependency|
        gem(*dependency) if defined?(gem)
        require(lib)
      end
    end
  end
end
```

### Error Handling (from `envkee`)

```ruby
module Shortbus
  class Error < ::StandardError
  end

  class ConnectionError < Error
  end

  class ConfigurationError < Error
  end

  # Raise specific errors with context
  def find_rendezvous!
    dir = ENV['SHORTBUS_ROOT'] || Dir.pwd

    unless File.exist?(File.join(dir, 'shortbus.yml'))
      raise ConfigurationError, "No shortbus.yml found in #{dir}"
    end

    dir
  end
end
```

### Method Aliasing (from `s3.rb`)

```ruby
module Shortbus
  def publish(topic, message)
    # Implementation
  end
  alias_method :pub, :publish

  def subscribe(topic, &block)
    # Implementation
  end
  alias_method :sub, :subscribe

  extend self
end
```

---

## File Structure Conventions

### Directory Layout (inspired by `ro`)

```
shortbus/
├── lib/
│   ├── shortbus.rb              # Main entry point
│   ├── shortbus/
│   │   ├── _lib.rb              # Dependency loader
│   │   ├── version.rb           # Version constant
│   │   ├── config.rb            # Configuration object
│   │   ├── engine.rb            # BlockQueue interface
│   │   ├── socket_server.rb    # Unix socket server
│   │   ├── file_watcher.rb     # File watching
│   │   ├── process_manager.rb  # Child process management
│   │   ├── tunnel/              # Tunnel adapters
│   │   │   ├── cloudflare.rb
│   │   │   └── ngrok.rb
│   │   └── cli/                 # CLI commands
│   │       ├── run.rb
│   │       ├── publish.rb
│   │       ├── subscribe.rb
│   │       └── console.rb
├── bin/
│   └── shortbus                 # Executable
├── rendezvous/                  # Working directory
│   ├── config/
│   ├── topics/
│   └── logs/
└── docs/
    ├── CONSTITUTION.md          # This file
    ├── SPEC.md                  # Specification
    └── RESEARCH.md              # Research notes
```

### Main Entry Point Pattern

```ruby
# lib/shortbus.rb
require_relative 'shortbus/_lib'

Shortbus.load_dependencies!

module Shortbus
  class << Shortbus
    def root
      config.root
    end

    def root=(path)
      config.root = path
    end

    # Core API
    def publish(topic, message, **opts)
      engine.publish(topic, message, **opts)
    end

    def subscribe(topic, &block)
      engine.subscribe(topic, &block)
    end

    def initialize!
      Shortbus.load %w[
        version.rb
        config.rb
        engine.rb
        socket_server.rb
        file_watcher.rb
        process_manager.rb
      ]

      Shortbus.log! if config.log
      Shortbus.debug! if config.debug
    end
  end
end

Shortbus.initialize!
```

---

## Coding Style Guidelines

### 1. **Naming Conventions**
- Methods: `snake_case`
- Classes: `PascalCase`
- Constants: `SCREAMING_SNAKE_CASE`
- Module methods: `snake_case`
- Private methods: Prefix with `_` (optional, use `private` keyword)

### 2. **Method Signatures**
- Use named parameters for clarity:
  ```ruby
  # Good
  def publish(topic, message, metadata: {}, priority: :normal)

  # Avoid
  def publish(topic, message, metadata = {}, priority = :normal)
  ```

- Use double splat for flexible options:
  ```ruby
  def write(key, body, **opts)
    opts[:content_type] ||= detect_content_type(key)
    # ...
  end
  ```

### 3. **Return Values**
- Explicit returns only when needed for clarity
- Return meaningful values (not just `true`/`nil`)
- Return hashes for multiple values:
  ```ruby
  def publish(topic, message)
    result = engine.publish(topic, message)
    { topic:, message_id: result[:id], timestamp: result[:timestamp] }
  end
  ```

### 4. **Error Handling**
- Raise specific exceptions with context
- Rescue at appropriate boundaries
- Don't swallow errors silently
  ```ruby
  def connect!
    client.connect
  rescue SocketError => e
    raise ConnectionError, "Failed to connect to engine: #{e.message}"
  end
  ```

### 5. **Configuration**
- ENV vars override config files
- Sensible defaults always
- Fail fast on misconfiguration
  ```ruby
  def port
    ENV['SHORTBUS_PORT']&.to_i || config.port || 8080
  end
  ```

### 6. **Logging and Debugging**
- Use standard Logger
- Debug mode via ENV or config
- Structured output when possible
  ```ruby
  def log!
    @logger = Logger.new($stdout)
    @logger.level = debug? ? Logger::DEBUG : Logger::INFO
  end

  def debug(msg)
    @logger&.debug("[shortbus] #{msg}")
  end
  ```

### 7. **Method Length**
- Prefer < 20 lines per method
- Extract helpers for complex logic
- Single Responsibility Principle

### 8. **Comments**
- Code should be self-documenting
- Comments explain *why*, not *what*
- Use YARD-style docs for public API:
  ```ruby
  # Publishes a message to the specified topic
  #
  # @param topic [String] the topic name
  # @param message [String, Hash] the message payload
  # @param metadata [Hash] optional message metadata
  # @return [Hash] publication result with :message_id and :timestamp
  def publish(topic, message, metadata: {})
    # Implementation
  end
  ```

---

## Testing Patterns (from `ro/test/`)

### Test Structure
```ruby
# test/test_helper.rb
require 'minitest/autorun'
require_relative '../lib/shortbus'

class ShortbusTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    Shortbus.root = @tmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end
end

# test/unit/engine_test.rb
require_relative '../test_helper'

class EngineTest < ShortbusTest
  def test_publish_returns_message_id
    result = Shortbus.publish('events', 'hello')
    assert result[:message_id]
  end
end
```

### Testing Principles
- Use Minitest (simple, built-in)
- Test behavior, not implementation
- Setup/teardown for clean state
- Integration tests in `test/integration/`
- Unit tests in `test/unit/`

---

## CLI Patterns (from `envkee`)

### CLI Structure
```ruby
module Shortbus
  module CLI
    TLDR = <<~____
      NAME
        shortbus - local-first message bus

      TL;DR
        ~> shortbus run                    # start daemon
        ~> shortbus publish events "msg"   # publish message
        ~> shortbus subscribe events       # subscribe to topic
        ~> shortbus console                # interactive REPL
    ____

    MODES = %w[ help run publish subscribe console stop ]

    def run!
      @mode = ARGV.shift || 'help'
      abort "unknown mode: #{@mode}" unless MODES.include?(@mode)

      send("run_#{@mode}!")
    rescue Shortbus::Error => e
      abort(e.message)
    end

    def run_help!
      abort TLDR
    end

    # Other mode implementations...

    extend self
  end
end

# bin/shortbus
#!/usr/bin/env ruby
require_relative '../lib/shortbus'
Shortbus::CLI.run!
```

---

## Git-Clone Install Pattern

### Executable Setup
```ruby
#!/usr/bin/env ruby

# bin/shortbus - Self-contained executable

# Ensure we're running from the project directory
LIB_DIR = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(LIB_DIR) unless $LOAD_PATH.include?(LIB_DIR)

begin
  require 'bundler/setup' if File.exist?(File.expand_path('../Gemfile', __dir__))
rescue LoadError
  # Bundler not available, try to load from system gems
end

require 'shortbus'

Shortbus::CLI.run!
```

### Directory Isolation
- All state in rendezvous directory
- PID files in rendezvous
- Logs in rendezvous/logs
- Config in rendezvous/config
- Never write outside project dir

---

## Modern Ruby Features to Use

### Named Parameters (Ruby 2.x+)
```ruby
def publish(topic, message, metadata: {}, priority: :normal)
  # ...
end
```

### Hash Shorthand (Ruby 3.1+)
```ruby
topic = 'events'
message_id = 123
{ topic:, message_id: }  # => { topic: 'events', message_id: 123 }
```

### Pattern Matching (Ruby 2.7+)
```ruby
case response
in { status: 'ok', data: }
  process(data)
in { status: 'error', error: message }
  log_error(message)
end
```

### Endless Methods (Ruby 3.0+)
```ruby
def topic = config.fetch(:topic)
def debug? = !!config.debug
```

### Ractors (Ruby 3.0+) - Use Sparingly
```ruby
# Only for CPU-intensive parallel work
ractor = Ractor.new do
  # Isolated computation
end
```

---

## Anti-Patterns to Avoid

### ❌ Don't: Global Mutable State
```ruby
# Bad
$SHORTBUS_CONFIG = {}

# Good
module Shortbus
  def config
    @config ||= Config.new
  end
  extend self
end
```

### ❌ Don't: Monkey Patch Core Classes
```ruby
# Bad
class String
  def to_topic
    # ...
  end
end

# Good
module Shortbus
  def self.normalize_topic(string)
    # ...
  end
end
```

### ❌ Don't: Deep Nesting
```ruby
# Bad
def process
  if condition1
    if condition2
      if condition3
        # ...
      end
    end
  end
end

# Good
def process
  return unless condition1
  return unless condition2
  return unless condition3
  # ...
end
```

### ❌ Don't: Silent Failures
```ruby
# Bad
def connect
  client.connect
rescue
  nil
end

# Good
def connect
  client.connect
rescue ConnectionError => e
  log_error("Connection failed: #{e.message}")
  raise
end
```

---

## Performance Considerations

### Lazy Loading
```ruby
def expensive_resource
  @expensive_resource ||= ExpensiveResource.new
end
```

### Batch Operations
```ruby
# Process in batches, don't load everything into memory
def process_messages(topic)
  loop do
    messages = fetch_batch(topic, limit: 100)
    break if messages.empty?

    messages.each { |msg| process(msg) }
  end
end
```

### Avoid String Allocations in Hot Paths
```ruby
# Use symbols for hash keys in hot paths
MESSAGE_FIELDS = %i[id topic payload timestamp].freeze

def parse_message(data)
  MESSAGE_FIELDS.each_with_object({}) do |field, result|
    result[field] = data[field.to_s]
  end
end
```

---

## Documentation Standards

### Public API
- YARD-style documentation
- Examples in docstrings
- Link to related methods

### README.md
- Quick start (< 5 minutes)
- TL;DR at top
- Examples before theory
- Personality okay, clarity first

### CHANGELOG.md
- Semantic versioning
- Keep-a-Changelog format
- Link to PRs/issues

---

## Version Control

### Commit Messages
- Present tense: "Add feature" not "Added feature"
- Imperative mood: "Fix bug" not "Fixes bug"
- First line < 72 chars
- Blank line, then details if needed

### Branching
- `main` - stable
- `feature/001-description` - feature branches
- Numbered features match `.specify` workflow

---

## Summary: The shortbus Way

1. **Simple** - Prefer clarity over cleverness
2. **Self-contained** - Everything in project directory
3. **Module-based** - Clean public API via modules
4. **Modern Ruby** - Use 3.2+ features tastefully
5. **Classic style** - Inspired by `ro`, `s3`, `envkee`
6. **Git-clone install** - Works from `git clone` + run
7. **Well-tested** - Minitest for behavior verification
8. **Well-documented** - Code explains itself, docs explain why

---

**This is the way.**
