module Shortbus
  VERSION = '0.1.0' unless defined?(VERSION)

  class << self
    def version
      VERSION
    end

    def repo
      'https://github.com/ahoward/shortbus'
    end

    def summary
      <<~____
        local-first message bus with cloud relay
      ____
    end

    def description
      <<~____
        shortbus is a durable pub/sub message bus built on SQLite/Turso with filesystem
        watching for reactive notifications. It runs as a sidecar process, supports multiple
        concurrent readers/writers, and provides local-first messaging with optional cloud
        relay capabilities.

        Architecture: Ruby wrapper around BlockQueue (Go + Turso)
      ____
    end
  end
end
