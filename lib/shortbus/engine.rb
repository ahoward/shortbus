module Shortbus
  # BlockQueue HTTP client
  # Simple wrapper around BlockQueue's REST API
  class Engine
    def initialize(base_url: nil, port: nil)
      @base_url = base_url || "http://localhost:#{port || Shortbus.config.engine_port}"
      @http_client = build_client
    end

    # Publish a message to a topic
    def publish(topic, payload, metadata: {}, trigger: true)
      uri = URI("#{@base_url}/topics/#{topic}/messages")

      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      request.body = JSON.generate({
        payload: payload.to_s,
        metadata: metadata
      })

      response = @http_client.request(request)

      case response
      when Net::HTTPSuccess
        result = JSON.parse(response.body, symbolize_names: true)
        response_data = {
          status: :ok,
          message_id: result[:id] || result[:message_id],
          topic: topic,
          timestamp: Time.now.to_i
        }

        # Trigger file watcher notification if enabled
        if trigger
          begin
            Shortbus.file_watcher.trigger!(topic, metadata: metadata)
          rescue => e
            # Don't fail publish if trigger fails
            Shortbus.warn "Failed to trigger file watcher: #{e.message}"
          end
        end

        response_data
      else
        raise EngineError, "Publish failed: #{response.code} #{response.body}"
      end
    rescue JSON::ParserError => e
      raise EngineError, "Invalid JSON response: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ConnectionError, "Cannot connect to BlockQueue at #{@base_url}: #{e.message}"
    end
    alias_method :pub, :publish

    # Fetch messages from a topic
    def fetch_messages(topic, offset: 0, limit: 100)
      uri = URI("#{@base_url}/topics/#{topic}/messages")
      uri.query = URI.encode_www_form(offset: offset, limit: limit)

      request = Net::HTTP::Get.new(uri)
      response = @http_client.request(request)

      case response
      when Net::HTTPSuccess
        result = JSON.parse(response.body, symbolize_names: true)
        messages = result[:messages] || result[:data] || []
        messages.map { |msg| normalize_message(msg, topic) }
      when Net::HTTPNotFound
        []
      else
        raise EngineError, "Fetch failed: #{response.code} #{response.body}"
      end
    rescue JSON::ParserError => e
      raise EngineError, "Invalid JSON response: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ConnectionError, "Cannot connect to BlockQueue: #{e.message}"
    end

    # Create a topic
    def create_topic(name, subscribers: [])
      uri = URI("#{@base_url}/topics")

      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      request.body = JSON.generate({
        name: name,
        subscribers: subscribers
      })

      response = @http_client.request(request)

      case response
      when Net::HTTPSuccess, Net::HTTPCreated
        { status: :ok, topic: name }
      else
        # Topic might already exist, that's okay
        if response.code == '409' || response.body.match?(/already exists/i)
          { status: :ok, topic: name, note: 'already exists' }
        else
          raise EngineError, "Create topic failed: #{response.code} #{response.body}"
        end
      end
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ConnectionError, "Cannot connect to BlockQueue: #{e.message}"
    end

    # List topics
    def list_topics
      uri = URI("#{@base_url}/topics")

      request = Net::HTTP::Get.new(uri)
      response = @http_client.request(request)

      case response
      when Net::HTTPSuccess
        result = JSON.parse(response.body, symbolize_names: true)
        result[:topics] || result[:data] || []
      else
        raise EngineError, "List topics failed: #{response.code} #{response.body}"
      end
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ConnectionError, "Cannot connect to BlockQueue: #{e.message}"
    end

    # Health check
    def healthy?
      uri = URI("#{@base_url}/health")

      request = Net::HTTP::Get.new(uri)
      response = @http_client.request(request)

      response.is_a?(Net::HTTPSuccess)
    rescue
      false
    end

    # Ping
    def ping
      healthy? ? { status: :ok } : { status: :error }
    end

    private

    def build_client
      uri = URI(@base_url)
      client = Net::HTTP.new(uri.host, uri.port)
      client.open_timeout = 5
      client.read_timeout = 30
      client
    end

    def normalize_message(msg, topic)
      {
        id: msg[:id],
        topic: topic,
        payload: msg[:payload] || msg[:body],
        metadata: msg[:metadata] || {},
        timestamp: msg[:timestamp] || msg[:created_at],
        sequence: msg[:sequence]
      }
    end
  end

  # Module-level access
  def engine
    @engine ||= Engine.new
  end

  def engine=(engine)
    @engine = engine
  end

  extend self
end
