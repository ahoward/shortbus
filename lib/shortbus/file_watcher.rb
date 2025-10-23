module Shortbus
  class FileWatcher
    attr_reader :config, :listener, :callbacks

    def initialize(config: Shortbus.config)
      @config = config
      @listener = nil
      @callbacks = {}
      @running = false
    end

    # Start watching for file changes
    def start!
      return false if @running

      ensure_topics_dir!

      Shortbus.info "Starting file watcher on #{config.topics_dir}..."

      @listener = Listen.to(config.topics_dir.to_s) do |modified, added, removed|
        handle_changes(modified: modified, added: added, removed: removed)
      end

      @listener.start
      @running = true

      Shortbus.info "File watcher started"
      true
    end

    # Stop watching
    def stop!
      return false unless @running

      Shortbus.info "Stopping file watcher..."

      @listener&.stop
      @running = false

      Shortbus.info "File watcher stopped"
      true
    end

    # Check if watcher is running
    def running?
      @running
    end

    # Register callback for topic changes
    #
    # Example:
    #   watcher.on_change('events') do |event|
    #     puts "Topic 'events' changed: #{event[:type]}"
    #   end
    def on_change(topic, &block)
      @callbacks[topic] ||= []
      @callbacks[topic] << block
    end

    # Remove all callbacks for a topic
    def remove_callbacks(topic)
      @callbacks.delete(topic)
    end

    # Trigger a notification (called when publishing)
    # This creates a trigger file that the file watcher will detect
    def trigger!(topic, metadata: {})
      ensure_topics_dir!

      trigger_file = trigger_path(topic)

      # Touch the trigger file to notify watchers
      FileUtils.mkdir_p(trigger_file.dirname)
      File.write(trigger_file, {
        topic: topic,
        timestamp: Time.now.utc.iso8601,
        metadata: metadata
      }.to_json)

      Shortbus.debug "Triggered file watcher for topic: #{topic}"
    end

    private

    def ensure_topics_dir!
      FileUtils.mkdir_p(config.topics_dir) unless config.topics_dir.exist?
    end

    # Handle file system changes
    def handle_changes(modified:, added:, removed:)
      # Process modified files
      modified.each do |path|
        handle_file_change(path, :modified)
      end

      # Process added files
      added.each do |path|
        handle_file_change(path, :added)
      end

      # Process removed files
      removed.each do |path|
        handle_file_change(path, :removed)
      end
    end

    # Handle individual file change
    def handle_file_change(path, change_type)
      pathname = Pathname.new(path)

      # Only handle trigger files
      return unless pathname.basename.to_s.start_with?('.trigger.')

      topic = extract_topic_from_path(pathname)
      return unless topic

      Shortbus.debug "File change detected: #{topic} (#{change_type})"

      # Read trigger file metadata if it exists
      metadata = {}
      if pathname.exist? && change_type != :removed
        begin
          data = JSON.parse(File.read(pathname), symbolize_names: true)
          metadata = data[:metadata] || {}
        rescue JSON::ParserError
          # Ignore invalid JSON
        end
      end

      # Trigger callbacks
      trigger_callbacks(topic, {
        type: change_type,
        topic: topic,
        path: pathname.to_s,
        metadata: metadata,
        timestamp: Time.now.utc.iso8601
      })
    end

    # Extract topic name from file path
    def extract_topic_from_path(pathname)
      # Path format: topics/.trigger.TOPIC_NAME
      basename = pathname.basename.to_s

      if basename =~ /^\.trigger\.(.+)$/
        $1
      else
        nil
      end
    end

    # Trigger all callbacks for a topic
    def trigger_callbacks(topic, event)
      callbacks = @callbacks[topic] || []

      callbacks.each do |callback|
        begin
          callback.call(event)
        rescue => e
          Shortbus.error "Error in file watcher callback for #{topic}: #{e.message}"
        end
      end

      # Also trigger wildcard callbacks (*)
      wildcard_callbacks = @callbacks['*'] || []
      wildcard_callbacks.each do |callback|
        begin
          callback.call(event)
        rescue => e
          Shortbus.error "Error in wildcard file watcher callback: #{e.message}"
        end
      end
    end

    # Get path for trigger file
    def trigger_path(topic)
      config.topics_dir / ".trigger.#{topic}"
    end
  end
end
