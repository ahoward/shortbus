module Shortbus
  module CLI
    TLDR = <<~____
      NAME
        shortbus - local-first message bus

      TL;DR
        ~> shortbus run                    # start daemon
        ~> shortbus pipe                   # pipe mode (JSONL stdin/stdout)
        ~> shortbus publish events "msg"   # publish message
        ~> shortbus subscribe events       # subscribe to topic
        ~> shortbus console                # interactive REPL
        ~> shortbus stop                   # stop daemon

      PIPE MODE (for integration)
        shortbus pipe mode uses JSONL (JSON Lines) for bidirectional communication:
          - Read from stdout: Receive messages
          - Write to stdin: Send commands

        Example (JavaScript):
          const shortbus = spawn('shortbus', ['pipe'])
          shortbus.stdout.on('data', line => { ... })
          shortbus.stdin.write(JSON.stringify({op: 'publish', ...}) + '\\n')

        Example (Python):
          proc = subprocess.Popen(['shortbus', 'pipe'], stdin=PIPE, stdout=PIPE)
          proc.stdin.write(json.dumps({op: 'publish', ...}) + '\\n')

        Example (Go):
          cmd := exec.Command("shortbus", "pipe")
          stdin, _ := cmd.StdinPipe()
          stdout, _ := cmd.StdoutPipe()

        See examples/ directory for full client implementations.

      PROTOCOL (pipe mode)
        All commands and responses are JSON objects, one per line (JSONL).

        Commands (stdin):
          {"op": "publish", "topic": "events", "payload": "hello"}
          {"op": "subscribe", "topic": "events"}
          {"op": "unsubscribe", "topic": "events"}
          {"op": "ping"}
          {"op": "shutdown"}

        Responses (stdout):
          {"status": "ok", "op": "published", "message_id": 123}
          {"type": "message", "topic": "events", "payload": "hello", "id": 123}
          {"type": "error", "error": "message"}
    ____

    MODES = %w[
      help
      version
      run
      pipe
      publish
      subscribe
      stop
      console
    ]

    def run!
      setup!
      run_mode!
    rescue Interrupt
      # Graceful shutdown on Ctrl-C
      exit(0)
    rescue Shortbus::Error => e
      abort(e.message)
    rescue => e
      abort("Fatal error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end

    def run_mode!
      unless MODES.include?(@mode.to_s)
        abort "Unknown mode: #{@mode}\nRun 'shortbus help' for usage."
      end

      send("run_#{@mode}!")
    end

    def run_help!
      abort TLDR
    end

    def run_version!
      puts "shortbus v#{Shortbus.version}"
      puts
      puts Shortbus.description
      exit(0)
    end

    def run_run!
      # Daemon mode: start BlockQueue and keep it running
      pm = Shortbus.process_manager

      if pm.running?
        puts "shortbus is already running"
        puts
        status = pm.status
        puts "  pid: #{status[:pid]}"
        puts "  port: #{status[:port]}"
        puts "  url: #{status[:url]}"
        exit(0)
      end

      puts "Starting shortbus..."

      # Ensure directory structure exists
      ensure_directories!

      # Start BlockQueue
      pm.start!

      status = pm.status
      puts "shortbus is running"
      puts
      puts "  pid: #{status[:pid]}"
      puts "  port: #{status[:port]}"
      puts "  url: #{status[:url]}"
      puts
      puts "Logs: #{Shortbus.config.engine_log_path}"
      puts
      puts "Use 'shortbus stop' to stop the service"
    rescue Shortbus::Error => e
      abort "Failed to start shortbus: #{e.message}"
    end

    def run_pipe!
      # Pipe mode: JSONL bidirectional communication
      Shortbus::PipeMode.new.run!
    end

    def run_publish!
      topic = ARGV.shift
      message = ARGV.shift

      unless topic && message
        abort "Usage: shortbus publish TOPIC MESSAGE"
      end

      # For now, use engine directly
      # In production, this would connect to running daemon
      result = Shortbus.engine.publish(topic, message)

      puts "Published to #{topic}: message_id=#{result[:message_id]}"
    rescue => e
      abort "Publish failed: #{e.message}"
    end

    def run_subscribe!
      topic = ARGV.shift

      unless topic
        abort "Usage: shortbus subscribe TOPIC"
      end

      puts "Subscribe mode not yet implemented"
      puts "Use 'shortbus pipe' for now"
      exit(1)
    end

    def run_stop!
      pm = Shortbus.process_manager

      unless pm.running?
        puts "shortbus is not running"
        exit(0)
      end

      status = pm.status
      puts "Stopping shortbus (pid: #{status[:pid]})..."

      if pm.stop!
        puts "shortbus stopped"
      else
        abort "Failed to stop shortbus"
      end
    end

    def run_console!
      puts "Console mode not yet implemented"
      puts "Use 'shortbus pipe' for now"
      exit(1)
    end

    def setup!
      @mode = ARGV.shift || 'help'
    end

    def ensure_directories!
      require 'fileutils'

      config = Shortbus.config

      [
        config.root_path,
        config.bin_path,
        config.config_dir,
        config.topics_dir,
        config.logs_dir,
      ].each do |dir|
        FileUtils.mkdir_p(dir) unless dir.exist?
      end
    end

    extend self
  end
end
