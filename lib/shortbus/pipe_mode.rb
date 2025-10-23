module Shortbus
  # Pipe mode: JSONL bidirectional communication via stdin/stdout
  #
  # This allows any language to integrate with shortbus using simple pipes:
  #   - Read from stdout: Receive messages (JSONL)
  #   - Write to stdin: Send commands (JSONL)
  #
  # Example (JavaScript):
  #   const shortbus = spawn('shortbus', ['pipe'])
  #   shortbus.stdout.on('data', (line) => { ... })
  #   shortbus.stdin.write(JSON.stringify({op: 'publish', ...}) + '\n')
  #
  # Example (Python):
  #   proc = subprocess.Popen(['shortbus', 'pipe'], stdin=PIPE, stdout=PIPE)
  #   proc.stdin.write(json.dumps({op: 'publish', ...}) + '\n')
  #   line = proc.stdout.readline()
  #
  # Example (Go):
  #   cmd := exec.Command("shortbus", "pipe")
  #   stdin, _ := cmd.StdinPipe()
  #   stdout, _ := cmd.StdoutPipe()
  #   ...
  class PipeMode
    def initialize
      @running = false
      @subscribers = Hash.new { |h, k| h[k] = [] }
      @stdin = $stdin
      @stdout = $stdout
      @stderr = $stderr
      @file_watcher_started = false
      @offsets = Hash.new(0)  # Track message offsets per topic
    end

    def run!
      @running = true

      # Start file watcher for reactive notifications
      start_file_watcher!

      # Send ready signal
      send_response(status: :ready, version: Shortbus.version)

      # Start input processor thread
      input_thread = Thread.new { process_input }

      # Keep alive
      input_thread.join
    rescue Interrupt
      shutdown!
    rescue => e
      send_error("Fatal error: #{e.message}")
      raise
    end

    def shutdown!
      @running = false

      # Stop file watcher
      begin
        Shortbus.file_watcher.stop! if @file_watcher_started
      rescue => e
        # Ignore shutdown errors
      end

      send_response(status: :shutdown)
    end

    private

    def process_input
      @stdin.each_line do |line|
        line = line.strip
        next if line.empty?

        begin
          command = JSON.parse(line, symbolize_names: true)
          handle_command(command)
        rescue JSON::ParserError => e
          send_error("Invalid JSON: #{e.message}", line: line)
        rescue => e
          send_error("Command error: #{e.message}", command: line)
        end
      end
    rescue IOError => e
      # stdin closed, shutdown gracefully
      shutdown!
    end

    def handle_command(cmd)
      op = cmd[:op] || cmd[:command]

      case op
      when 'publish', 'pub'
        handle_publish(cmd)

      when 'subscribe', 'sub'
        handle_subscribe(cmd)

      when 'unsubscribe', 'unsub'
        handle_unsubscribe(cmd)

      when 'list_topics', 'topics'
        handle_list_topics(cmd)

      when 'ping'
        handle_ping(cmd)

      when 'shutdown', 'quit', 'exit'
        shutdown!

      else
        send_error("Unknown operation: #{op}", command: cmd)
      end
    rescue => e
      send_error("Operation failed: #{e.message}", command: cmd, error: e.class.name)
    end

    def handle_publish(cmd)
      topic = cmd[:topic] || cmd[:t]
      payload = cmd[:payload] || cmd[:message] || cmd[:msg]
      metadata = cmd[:metadata] || cmd[:meta] || {}

      raise ArgumentError, "Missing topic" unless topic
      raise ArgumentError, "Missing payload" unless payload

      result = Shortbus.engine.publish(topic, payload, metadata: metadata)

      send_response(
        status: :ok,
        op: :published,
        topic: topic,
        message_id: result[:message_id],
        request_id: cmd[:request_id]
      )

    rescue => e
      send_error("Publish failed: #{e.message}", command: cmd)
    end

    def handle_subscribe(cmd)
      topic = cmd[:topic] || cmd[:t]
      raise ArgumentError, "Missing topic" unless topic

      # Create topic if doesn't exist
      begin
        Shortbus.engine.create_topic(topic)
      rescue => e
        # Ignore if already exists
      end

      # Add to subscribers
      @subscribers[topic] << {
        request_id: cmd[:request_id],
        offset: cmd[:offset] || 0
      }

      send_response(
        status: :ok,
        op: :subscribed,
        topic: topic,
        request_id: cmd[:request_id]
      )

      # Start watching for messages
      start_message_watcher(topic)

    rescue => e
      send_error("Subscribe failed: #{e.message}", command: cmd)
    end

    def handle_unsubscribe(cmd)
      topic = cmd[:topic] || cmd[:t]
      raise ArgumentError, "Missing topic" unless topic

      @subscribers.delete(topic)

      send_response(
        status: :ok,
        op: :unsubscribed,
        topic: topic,
        request_id: cmd[:request_id]
      )
    end

    def handle_list_topics(cmd)
      topics = Shortbus.engine.list_topics

      send_response(
        status: :ok,
        op: :topics,
        topics: topics,
        request_id: cmd[:request_id]
      )
    rescue => e
      send_error("List topics failed: #{e.message}", command: cmd)
    end

    def handle_ping(cmd)
      result = Shortbus.engine.ping

      send_response(
        status: :ok,
        op: :pong,
        engine_status: result[:status],
        request_id: cmd[:request_id]
      )
    rescue => e
      send_error("Ping failed: #{e.message}", command: cmd)
    end

    def start_file_watcher!
      return if @file_watcher_started

      begin
        Shortbus.file_watcher.start!
        @file_watcher_started = true
      rescue => e
        Shortbus.warn "Failed to start file watcher: #{e.message}"
        # Continue without file watcher (will use polling fallback)
      end
    end

    def start_message_watcher(topic)
      # Register file watcher callback for reactive notifications
      if @file_watcher_started
        Shortbus.file_watcher.on_change(topic) do |event|
          fetch_and_send_messages(topic) if @running && @subscribers[topic].any?
        end
      end

      # Initial fetch of existing messages
      fetch_and_send_messages(topic)

      # Fallback polling thread if file watcher isn't available
      unless @file_watcher_started
        Thread.new do
          while @running && @subscribers[topic].any?
            begin
              fetch_and_send_messages(topic)
              sleep 0.1  # Poll interval
            rescue => e
              send_error("Watcher error: #{e.message}", topic: topic)
              break
            end
          end
        end
      end
    end

    def fetch_and_send_messages(topic)
      offset = @offsets[topic]

      begin
        messages = Shortbus.engine.fetch_messages(topic, offset: offset)

        messages.each do |msg|
          send_message(msg)
          @offsets[topic] = [offset, msg[:id] + 1].max if msg[:id]
        end
      rescue => e
        send_error("Fetch error: #{e.message}", topic: topic)
      end
    end

    def send_message(msg)
      send_response(
        type: :message,
        topic: msg[:topic],
        id: msg[:id],
        payload: msg[:payload],
        metadata: msg[:metadata],
        timestamp: msg[:timestamp],
        sequence: msg[:sequence]
      )
    end

    def send_response(data)
      line = JSON.generate(data)
      @stdout.puts(line)
      @stdout.flush
    end

    def send_error(message, **context)
      send_response(
        type: :error,
        error: message,
        **context
      )
    end
  end

  extend self
end
