module Shortbus
  class ProcessManager
    attr_reader :pid, :config

    def initialize(config: Shortbus.config)
      @config = config
      @pid = nil
      @process = nil
    end

    # Start BlockQueue process
    def start!
      ensure_binary!
      ensure_config!
      run_migration!

      if running?
        Shortbus.warn "BlockQueue already running (pid: #{@pid})"
        return false
      end

      # Remove stale PID file if exists
      remove_pidfile! if pidfile_exists? && !process_running?(read_pidfile)

      Shortbus.info "Starting BlockQueue on port #{config.engine_port}..."

      @pid = spawn_blockqueue
      write_pidfile!

      # Wait for engine to be ready
      wait_for_ready!

      Shortbus.info "BlockQueue started (pid: #{@pid})"
      true
    rescue => e
      Shortbus.error "Failed to start BlockQueue: #{e.message}"
      cleanup!
      raise EngineError, "Failed to start BlockQueue: #{e.message}"
    end

    # Stop BlockQueue process
    def stop!
      unless running?
        Shortbus.warn "BlockQueue not running"
        return false
      end

      Shortbus.info "Stopping BlockQueue (pid: #{@pid})..."

      begin
        Process.kill('TERM', @pid)

        # Wait for graceful shutdown (up to 5 seconds)
        5.times do
          sleep 1
          unless process_running?(@pid)
            Shortbus.info "BlockQueue stopped gracefully"
            cleanup!
            return true
          end
        end

        # Force kill if still running
        if process_running?(@pid)
          Shortbus.warn "Force killing BlockQueue..."
          Process.kill('KILL', @pid)
          sleep 1
        end

        cleanup!
        Shortbus.info "BlockQueue stopped"
        true
      rescue Errno::ESRCH
        # Process already dead
        cleanup!
        true
      rescue => e
        Shortbus.error "Error stopping BlockQueue: #{e.message}"
        cleanup!
        false
      end
    end

    # Check if BlockQueue is running
    def running?
      return false unless pidfile_exists?

      pid = read_pidfile
      return false unless pid

      process_running?(pid) && engine_responding?
    end

    # Get process status
    def status
      if running?
        {
          status: :running,
          pid: @pid || read_pidfile,
          port: config.engine_port,
          url: "http://localhost:#{config.engine_port}"
        }
      else
        {
          status: :stopped
        }
      end
    end

    private

    # Spawn BlockQueue process
    def spawn_blockqueue
      # BlockQueue requires: blockqueue http --config <path>
      # Use absolute paths
      bin = File.expand_path(binary_path.to_s)
      cfg = File.expand_path(config.blockqueue_config_path.to_s)
      log = File.expand_path(config.engine_log_path.to_s)
      workdir = File.expand_path(config.root_path.to_s)

      cmd = [bin, 'http', '--config', cfg]

      pid = Process.spawn(
        *cmd,
        out: log,
        err: log,
        pgroup: true,  # Create new process group
        chdir: workdir  # Run from rendezvous directory
      )

      Process.detach(pid)  # Don't wait for child process
      pid
    end

    # Wait for engine to be ready (respond to HTTP)
    def wait_for_ready!(timeout: 10)
      start_time = Time.now

      loop do
        return true if engine_responding?

        if Time.now - start_time > timeout
          raise EngineError, "BlockQueue failed to start within #{timeout} seconds"
        end

        sleep 0.5
      end
    end

    # Check if engine responds to HTTP requests
    def engine_responding?
      uri = URI("http://localhost:#{config.engine_port}/health")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue
      false
    end

    # Check if process is running by PID
    def process_running?(pid)
      return false unless pid

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      # Process exists but we don't have permission (still running)
      true
    end

    # Ensure BlockQueue binary exists
    def ensure_binary!
      return if binary_path.exist?

      Shortbus.info "BlockQueue binary not found, downloading..."
      download_binary!
    end

    # Ensure BlockQueue config exists
    def ensure_config!
      return if config.blockqueue_config_path.exist?

      Shortbus.info "Creating default BlockQueue config..."
      FileUtils.mkdir_p(config.config_dir)

      default_config = <<~YAML
        http:
          port: #{config.engine_port}
          shutdown: "30s"
          driver: "sqlite"
        logging:
          level: "info"
          type: "json"
        sqlite:
          db_name: "blockqueue"
          busy_timeout: 5000
        job:
          producer_partition: 16
          consumer_partition: 16
        etcd:
          path: "etcdb"
          sync: false
        metric:
          enable: false
      YAML

      File.write(config.blockqueue_config_path, default_config)
    end

    # Run database migration
    def run_migration!
      bin = File.expand_path(binary_path.to_s)
      cfg = File.expand_path(config.blockqueue_config_path.to_s)
      workdir = File.expand_path(config.root_path.to_s)

      Shortbus.debug "Running BlockQueue migration..."

      # Run migration in the rendezvous directory
      system(bin, 'migrate', '--config', cfg, chdir: workdir, out: File::NULL, err: File::NULL)
    end

    # Download BlockQueue binary
    def download_binary!
      require 'open-uri'
      require 'fileutils'

      FileUtils.mkdir_p(config.bin_path)

      # Determine platform
      os = case RUBY_PLATFORM
      when /darwin/
        'darwin'
      when /linux/
        'linux'
      else
        raise ConfigurationError, "Unsupported platform: #{RUBY_PLATFORM}"
      end

      arch = case RUBY_PLATFORM
      when /x86_64|amd64/
        'amd64'
      when /arm64|aarch64/
        'arm64'
      else
        raise ConfigurationError, "Unsupported architecture: #{RUBY_PLATFORM}"
      end

      # Download from GitHub releases
      version = 'latest'  # Could make this configurable
      filename = "blockqueue-#{os}-#{arch}"
      url = "https://github.com/yudhasubki/blockqueue/releases/download/#{version}/#{filename}"

      Shortbus.info "Downloading from #{url}..."

      begin
        URI.open(url) do |remote|
          File.open(binary_path, 'wb') do |local|
            local.write(remote.read)
          end
        end

        FileUtils.chmod(0755, binary_path)
        Shortbus.info "BlockQueue binary downloaded successfully"
      rescue => e
        raise ConfigurationError, "Failed to download BlockQueue binary: #{e.message}"
      end
    end

    # Binary path
    def binary_path
      config.bin_path / 'blockqueue'
    end

    # PID file operations
    def pidfile_path
      config.root_path / 'blockqueue.pid'
    end

    def pidfile_exists?
      pidfile_path.exist?
    end

    def read_pidfile
      return nil unless pidfile_exists?

      pid = File.read(pidfile_path).strip.to_i
      pid > 0 ? pid : nil
    rescue
      nil
    end

    def write_pidfile!
      File.write(pidfile_path, @pid.to_s)
    end

    def remove_pidfile!
      pidfile_path.delete if pidfile_exists?
    rescue
      # Ignore errors
    end

    def cleanup!
      @pid = nil
      remove_pidfile!
    end
  end
end
