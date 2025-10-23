require_relative 'shortbus/_lib'

Shortbus.load_dependencies!

module Shortbus
  # Errors
  class Error < ::StandardError
  end

  class ConfigurationError < Error
  end

  class ConnectionError < Error
  end

  class EngineError < Error
  end

  class << Shortbus
    # Configuration
    def config
      @config ||= Config.new
    end

    def config=(value)
      @config = value
    end

    def root
      config.root
    end

    def root=(path)
      config.root = path
    end

    # Logging
    def logger
      @logger
    end

    def log!
      @logger = Logger.new($stdout)
      @logger.level = debug? ? Logger::DEBUG : Logger::INFO
      @logger
    end

    def debug!
      config.debug = true
      log!
      @logger.level = Logger::DEBUG
    end

    def debug?
      config.debug?
    end

    def debug(msg)
      @logger&.debug("[shortbus] #{msg}")
    end

    def info(msg)
      @logger&.info("[shortbus] #{msg}")
    end

    def warn(msg)
      @logger&.warn("[shortbus] #{msg}")
    end

    def error(msg)
      @logger&.error("[shortbus] #{msg}")
    end

    # Engine (BlockQueue wrapper)
    def engine
      @engine ||= Engine.new
    end

    # Process manager
    def process_manager
      @process_manager ||= ProcessManager.new
    end

    # File watcher
    def file_watcher
      @file_watcher ||= FileWatcher.new
    end

    # Initialization
    def initialize!
      Shortbus.load %w[
        version.rb
        config.rb
        engine.rb
        process_manager.rb
        file_watcher.rb
        pipe_mode.rb
      ]

      Shortbus.log! if config.log?
      Shortbus.debug! if config.debug?
    end
  end
end

Shortbus.initialize!
