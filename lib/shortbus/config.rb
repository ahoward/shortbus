module Shortbus
  class Config
    attr_accessor :root, :port, :log, :debug, :engine_port

    def initialize
      @root = env.root || defaults.root
      @port = env.port || defaults.port
      @log = env.log || defaults.log
      @debug = env.debug || defaults.debug
      @engine_port = env.engine_port || defaults.engine_port
    end

    def env
      Map.for({
        root: ENV['SHORTBUS_ROOT'],
        port: ENV['SHORTBUS_PORT']&.to_i,
        log: ENV['SHORTBUS_LOG'],
        debug: ENV['SHORTBUS_DEBUG'],
        engine_port: ENV['SHORTBUS_ENGINE_PORT']&.to_i,
      })
    end

    def defaults
      Map.for({
        root: './rendezvous',
        port: 9090,
        log: nil,
        debug: nil,
        engine_port: 8080,  # BlockQueue default port
      })
    end

    def root_path
      Pathname.new(@root)
    end

    def bin_path
      root_path / 'bin'
    end

    def config_dir
      root_path / 'config'
    end

    def topics_dir
      root_path / 'topics'
    end

    def topics_path
      topics_dir
    end

    def logs_dir
      root_path / 'logs'
    end

    def socket_path
      root_path / 'shortbus.sock'
    end

    def pid_file
      root_path / 'shortbus.pid'
    end

    def engine_pid_file
      root_path / 'blockqueue.pid'
    end

    def engine_log_path
      logs_dir / 'blockqueue.log'
    end

    def shortbus_yml
      config_dir / 'shortbus.yml'
    end

    def blockqueue_yml
      config_dir / 'blockqueue.yml'
    end

    def blockqueue_config_path
      blockqueue_yml
    end

    def debug?
      !!@debug
    end

    def log?
      !!@log
    end
  end
end
