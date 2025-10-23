# shortbus Wrapper Architecture: Deep Analysis

**Date**: 2025-10-20
**Proposal**: Wrap BlockQueue as the engine, layer shortbus features on top

---

## Executive Summary

**The wrapper architecture is BRILLIANT and highly viable.** This approach:

1. ✅ **Leverages existing production code** (BlockQueue + Turso)
2. ✅ **Preserves shortbus philosophy** (filesystem, Unix sockets, file watching)
3. ✅ **Enables rapid development** (2-4 weeks to MVP instead of 4-8 weeks)
4. ✅ **Allows language flexibility** (Ruby OR Go, both work)
5. ✅ **Future-proof** (can swap engines later if needed)

**Recommendation**: **Build shortbus as a facade/adapter wrapper around BlockQueue**

---

## Table of Contents

1. [Architectural Analysis](#1-architectural-analysis)
2. [Wrapper Pattern Deep Dive](#2-wrapper-pattern-deep-dive)
3. [BlockQueue as Engine](#3-blockqueue-as-engine)
4. [shortbus Wrapper Layer](#4-shortbus-wrapper-layer)
5. [Ruby vs Go for Wrapper](#5-ruby-vs-go-for-wrapper)
6. [Tunnel Adapter Pattern](#6-tunnel-adapter-pattern)
7. [Implementation Strategy](#7-implementation-strategy)
8. [Code Examples](#8-code-examples)
9. [Risk Analysis](#9-risk-analysis)
10. [Final Recommendation](#10-final-recommendation)

---

## 1. Architectural Analysis

### 1.1 The Facade/Adapter Pattern for Services

**What you're describing is a classic microservices pattern:**

```
┌─────────────────────────────────────────────────┐
│              shortbus (Facade)                  │
│                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────┐│
│  │ Unix Socket │  │ File Watch  │  │ Rendez- ││
│  │   Server    │  │  (inotify)  │  │  vous   ││
│  └──────┬──────┘  └──────┬──────┘  │  Dir    ││
│         │                │          └────┬────┘│
│         └────────┬───────┘               │     │
│                  │                       │     │
│           ┌──────▼───────────────────────▼───┐ │
│           │  HTTP Client (localhost:PORT)    │ │
│           └──────┬───────────────────────────┘ │
└──────────────────┼─────────────────────────────┘
                   │ HTTP/REST
            ┌──────▼───────┐
            │  BlockQueue  │ ◄──── The Engine
            │   (Go)       │       (Turso, SQLite, NutsDB)
            └──────────────┘
```

**Pattern Name**: **Service Facade with Adapter**

**Benefits**:
1. ✅ **Separation of concerns**: shortbus = UX layer, BlockQueue = storage engine
2. ✅ **Testability**: Mock HTTP calls to BlockQueue for testing
3. ✅ **Swappability**: Replace BlockQueue with another engine later
4. ✅ **Polyglot**: Wrapper can be Ruby, engine is Go (best of both)
5. ✅ **Clear boundaries**: HTTP API = contract between layers

### 1.2 Why This Works

**BlockQueue provides**:
- ✅ Durable storage (Turso concurrent writes, SQLite WAL)
- ✅ Pub/sub mechanism (topics, subscribers)
- ✅ Job queue (retry logic, visibility timeout)
- ✅ HTTP API (simple, well-defined interface)
- ✅ Multi-backend (SQLite, Turso, NutsDB, PostgreSQL)

**shortbus wrapper adds**:
- ✅ Unix domain socket IPC (faster than HTTP for localhost)
- ✅ File watching (inotify/fswatch for reactive notifications)
- ✅ Rendezvous directory (filesystem-based discovery)
- ✅ Git-based installation (`git clone` + run)
- ✅ Process management (spawn BlockQueue, supervise)
- ✅ Tunnel adapters (ngrok, Cloudflare for POS/edge)
- ✅ Ruby/Go SDK (elegant API, not just HTTP client)

**This is composition over inheritance** - a foundational design principle.

---

## 2. Wrapper Pattern Deep Dive

### 2.1 Facade Pattern (GoF)

**Intent**: Provide a unified interface to a set of interfaces in a subsystem. Facade defines a higher-level interface that makes the subsystem easier to use.

**In shortbus**:
- **Subsystem**: BlockQueue HTTP API
- **Facade**: shortbus (Unix socket + file watching + rendezvous dir)
- **Higher-level interface**: `shortbus publish`, `shortbus subscribe` (vs raw HTTP)

### 2.2 Adapter Pattern (GoF)

**Intent**: Convert the interface of a class into another interface clients expect. Adapter lets classes work together that couldn't otherwise because of incompatible interfaces.

**In shortbus**:
- **Adaptee**: BlockQueue HTTP API (RESTful JSON)
- **Target**: shortbus API (Unix socket, file-based)
- **Adapter**: shortbus wrapper layer

### 2.3 Why NOT Proxy Pattern

**Proxy Pattern**: Same interface, adds behavior (caching, security, lazy loading).
**Why not**: shortbus intentionally changes the interface (HTTP → Unix socket + files).

**Verdict**: **Facade + Adapter hybrid** (common in real-world systems)

### 2.4 Real-World Examples

**This pattern is proven in production**:

1. **Redis**: redis-cli wraps Redis server (RESP protocol)
2. **Docker**: docker CLI wraps Docker daemon (HTTP API)
3. **Kafka**: kafka-console-* tools wrap Kafka brokers (binary protocol)
4. **AWS CLI**: wraps AWS APIs (HTTP REST)
5. **kubectl**: wraps Kubernetes API server (HTTP/gRPC)

**All these are facades/adapters around an engine.**

---

## 3. BlockQueue as Engine

### 3.1 Can BlockQueue be Driven via CLI?

**From research**: BlockQueue is primarily HTTP-driven, BUT:

**Option 1: Build thin CLI wrapper**
```bash
# blockqueue-cli (simple curl wrapper)
blockqueue publish --topic events --message "hello"
# Under the hood:
# curl -X POST http://localhost:8080/topics/events/messages -d '{"message":"hello"}'
```

**Option 2: Use BlockQueue's API directly**
```bash
# Direct HTTP calls (what we'll do from shortbus)
curl -X POST http://localhost:8080/topics/events/messages \
  -H "Content-Type: application/json" \
  -d '{"payload": "hello", "metadata": {}}'
```

**Option 3: Embed BlockQueue as library**
```go
// If BlockQueue exports a library interface
import "github.com/yudhasubki/blockqueue/lib"

queue := blockqueue.New(config)
queue.Publish("events", message)
```

**Verdict**: **Direct HTTP API is simplest** (already documented, stable interface)

### 3.2 BlockQueue HTTP API (Inferred from Documentation)

**Based on research, BlockQueue likely has:**

```
POST   /topics                    # Create topic
GET    /topics                    # List topics
GET    /topics/:name              # Get topic details
DELETE /topics/:name              # Delete topic

POST   /topics/:name/subscribers  # Create subscriber
GET    /topics/:name/subscribers  # List subscribers
DELETE /topics/:name/subscribers/:id  # Delete subscriber

POST   /topics/:name/messages     # Publish message
GET    /topics/:name/messages     # Poll messages (for subscriber)
PUT    /topics/:name/messages/:id # Ack message
DELETE /topics/:name/messages/:id # Nack message (retry)
```

**This is a clean, RESTful API** - perfect for wrapping.

### 3.3 BlockQueue Process Management

**shortbus will manage BlockQueue as a child process:**

**Go (os/exec)**:
```go
cmd := exec.Command("blockqueue", "--config", "config.yaml")
cmd.Stdout = logFile
cmd.Stderr = logFile
cmd.Start()

// Save PID for later
pid := cmd.Process.Pid
```

**Ruby (Process.spawn + daemons gem)**:
```ruby
require 'daemons'

Daemons.run_proc('blockqueue') do
  exec 'blockqueue', '--config', 'config.yaml'
end
```

**Advantages of wrapper managing BlockQueue**:
1. ✅ **User never sees BlockQueue** (implementation detail)
2. ✅ **Auto-restart on crash** (supervisor pattern)
3. ✅ **Single install** (`git clone shortbus`, not `install blockqueue + shortbus`)
4. ✅ **Config management** (shortbus generates BlockQueue config)
5. ✅ **Lifecycle control** (shortbus start/stop controls both)

---

## 4. shortbus Wrapper Layer

### 4.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                  shortbus Wrapper                   │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │           Rendezvous Directory               │  │
│  │  rendezvous/                                 │  │
│  │    ├── shortbus.pid                          │  │
│  │    ├── shortbus.sock   ◄──── Unix socket    │  │
│  │    ├── topics/                               │  │
│  │    │   ├── events.trigger  ◄── File watch   │  │
│  │    │   └── logs.trigger                      │  │
│  │    └── config/                               │  │
│  │        ├── shortbus.yml                      │  │
│  │        └── blockqueue.yml  ◄── Generated    │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ Unix Socket  │  │ File Watcher │  │ Process  │ │
│  │   Server     │  │  (inotify)   │  │ Manager  │ │
│  └──────┬───────┘  └──────┬───────┘  └────┬─────┘ │
│         │                 │                │       │
│         └─────────┬───────┴────────────────┘       │
│                   │                                 │
│            ┌──────▼─────────┐                      │
│            │ BlockQueue API │                      │
│            │    Client      │                      │
│            └──────┬─────────┘                      │
└────────────────────┼──────────────────────────────┘
                     │ HTTP (localhost:8080)
              ┌──────▼──────────┐
              │  BlockQueue     │
              │  (child process)│
              │                 │
              │  ┌───────────┐  │
              │  │   Turso   │  │
              │  │ (embedded │  │
              │  │  replica) │  │
              │  └───────────┘  │
              └─────────────────┘
```

### 4.2 Component Responsibilities

**1. Unix Socket Server**
- **Purpose**: Fast local IPC (41 Gbits/s vs HTTP overhead)
- **Protocol**: Length-prefix JSON or text-based (NATS-style)
- **Listens**: `rendezvous/shortbus.sock`
- **Translates**: Unix socket commands → HTTP calls to BlockQueue

**2. File Watcher**
- **Purpose**: Reactive notifications (not polling)
- **Watches**: `rendezvous/topics/*.trigger` files
- **On change**: Notify subscribers via Unix socket
- **Implementation**: `listen` gem (Ruby) or `fsnotify` (Go)

**3. Process Manager**
- **Purpose**: Spawn and supervise BlockQueue
- **Responsibilities**:
  - Start BlockQueue on `shortbus run`
  - Monitor health (HTTP /health endpoint?)
  - Restart on crash
  - Stop on `shortbus stop`
  - Write PID file (`shortbus.pid`)
- **Implementation**: `daemons` gem (Ruby) or `os/exec` (Go)

**4. BlockQueue API Client**
- **Purpose**: HTTP client for BlockQueue API
- **Responsibilities**:
  - Publish: `POST /topics/:topic/messages`
  - Subscribe: `GET /topics/:topic/messages` (poll)
  - Manage topics/subscribers
- **Implementation**: `net/http` (Go) or `http` (Ruby stdlib)

**5. Trigger File Manager**
- **Purpose**: Touch files on publish to notify watchers
- **Responsibilities**:
  - After HTTP publish → touch `topics/:topic.trigger`
  - File watcher reacts → notify Unix socket subscribers
- **Why**: BlockQueue (HTTP) doesn't push notifications, we add reactivity

### 4.3 Message Flow

**Publish**:
```
App → Unix socket (shortbus.sock)
  → shortbus receives "PUB events hello"
  → HTTP POST to BlockQueue (localhost:8080/topics/events/messages)
  → BlockQueue writes to Turso
  → shortbus touches rendezvous/topics/events.trigger
  → File watcher detects change
  → Notify subscribers on Unix socket
```

**Subscribe** (reactive):
```
App → Unix socket "SUB events"
  → shortbus registers subscriber
  → File watcher on events.trigger triggers:
    → HTTP GET to BlockQueue (fetch new messages)
    → Stream to app via Unix socket
```

**Subscribe** (polling fallback):
```
App → HTTP GET to BlockQueue directly (optional)
OR
shortbus → Periodic HTTP GET to BlockQueue
         → Cache locally, stream via Unix socket
```

### 4.4 Configuration Management

**shortbus.yml** (user-facing):
```yaml
# rendezvous/config/shortbus.yml
engine: blockqueue  # Future: could be "sqlite", "nats", etc.

blockqueue:
  driver: turso
  turso:
    url: libsql://your-db.turso.io
    auth_token: ${TURSO_AUTH_TOKEN}

  # Or local SQLite
  # driver: sqlite
  # sqlite:
  #   path: ./data/shortbus.db

socket:
  path: rendezvous/shortbus.sock
  protocol: json  # or "text" (NATS-style)

file_watch:
  enabled: true
  triggers_dir: rendezvous/topics

tunnel:
  enabled: false
  # adapter: cloudflare  # or ngrok
  # cloudflare:
  #   ...
```

**blockqueue.yml** (generated by shortbus):
```yaml
# Generated from shortbus.yml
http:
  port: 8080
  driver: turso
  url: libsql://your-db.turso.io
  auth_token: ${TURSO_AUTH_TOKEN}
```

**Benefit**: User only edits shortbus.yml, wrapper generates BlockQueue config.

---

## 5. Ruby vs Go for Wrapper

### 5.1 The Case for Ruby

**Pros**:
1. ✅ **Author's expertise** (all samples are Ruby: ro, map gems)
2. ✅ **Rapid development**: 2-3 weeks to working wrapper
3. ✅ **Excellent libraries**:
   - `daemons` gem (process supervision)
   - `listen` gem (file watching)
   - `socket` stdlib (Unix sockets)
   - `net/http` stdlib (HTTP client)
4. ✅ **Elegant API**: Metaprogramming for DSL (like ro gem)
5. ✅ **Simple deployment**: `gem install` or `git clone` + `bundle install`
6. ✅ **Script-friendly**: Easy to shell out to BlockQueue binary
7. ✅ **Perfect for facade**: Ruby excels at wrapper/adapter code

**Cons**:
1. ❌ **Performance**: Wrapper overhead (but minimal - just IPC translation)
2. ❌ **Memory**: 50MB+ (but BlockQueue does heavy lifting)

**When wrapper is thin** (just IPC → HTTP translation), Ruby overhead is negligible.

### 5.2 The Case for Go

**Pros**:
1. ✅ **Same language as BlockQueue**: Could import as library later
2. ✅ **Static binary**: Single executable (no Ruby runtime)
3. ✅ **Performance**: Fast IPC, low memory (10-20MB)
4. ✅ **Channels**: Natural for async notifications
5. ✅ **Goroutines**: Handle thousands of concurrent subscribers

**Cons**:
1. ❌ **Not author's primary language**
2. ❌ **Slower development**: 4-5 weeks vs Ruby's 2-3 weeks
3. ❌ **Verbosity**: More boilerplate than Ruby
4. ❌ **Less elegant**: No Ruby-style DSL/metaprogramming

### 5.3 Performance Reality Check

**Is Ruby fast enough for a wrapper?**

**Yes, because**:
1. **Wrapper is thin**: Just translates IPC → HTTP
2. **BlockQueue does heavy lifting**: Storage, Turso sync, etc.
3. **Unix socket is fast**: 41 Gbits/s (bottleneck is BlockQueue HTTP, not Ruby)
4. **File watching is event-driven**: Not CPU-intensive

**Napkin math**:
- Unix socket recv: ~0.1ms
- Parse command: ~0.01ms
- HTTP call to BlockQueue: ~1-2ms (localhost)
- Touch trigger file: ~0.1ms
- **Total overhead**: ~1-2ms (dominated by HTTP, not Ruby)

**Compared to direct BlockQueue** (no wrapper):
- Direct HTTP: ~1-2ms
- Via shortbus wrapper: ~3-4ms
- **Overhead**: ~1-2ms (acceptable for local messaging)

**Verdict**: **Ruby is fast enough** (wrapper doesn't need to be faster than engine)

### 5.4 Hybrid Approach

**Best of both worlds**:
```
Ruby wrapper (initial MVP, 2-3 weeks)
  ↓
Profile and benchmark
  ↓
If wrapper is bottleneck (unlikely):
  → Rewrite wrapper in Go (keep API)
  → OR embed BlockQueue as Go library
```

**Most likely**: Ruby wrapper is sufficient forever.

---

## 6. Tunnel Adapter Pattern

### 6.1 POS/Edge Architecture

**Your insight about POS is brilliant**:
- **Point of Sale** terminals often run on isolated networks
- **Need to expose** local services for remote management
- **Tunnels** (ngrok, Cloudflare) are perfect for this

**Architecture**:
```
┌─────────────────────┐
│   POS Terminal      │
│   (edge device)     │
│                     │
│  ┌──────────────┐   │
│  │  shortbus    │   │
│  │  (wrapper)   │   │
│  └──────┬───────┘   │
│         │           │
│  ┌──────▼───────┐   │
│  │ BlockQueue   │   │
│  │ (localhost)  │   │
│  └──────┬───────┘   │
└─────────┼───────────┘
          │
    ┌─────▼──────┐
    │ Cloudflare │
    │  Tunnel    │
    └─────┬──────┘
          │ HTTPS
    ┌─────▼──────┐
    │   Cloud    │
    │ (HQ, APIs) │
    └────────────┘
```

### 6.2 Tunnel Adapter Implementation

**Cloudflare Tunnel**:
```bash
# shortbus starts tunnel adapter
cloudflared tunnel --url http://localhost:8080
# Returns: https://random-subdomain.trycloudflare.com
```

**ngrok**:
```bash
ngrok http 8080
# Returns: https://abc123.ngrok.io
```

**shortbus wrapper manages tunnel**:
```ruby
# lib/shortbus/tunnel/cloudflare.rb
class Shortbus::Tunnel::Cloudflare
  def start(local_port)
    cmd = "cloudflared tunnel --url http://localhost:#{local_port}"
    @tunnel_pid = Process.spawn(cmd, out: 'tunnel.log', err: 'tunnel.log')

    # Parse log for public URL
    sleep 2
    @public_url = File.read('tunnel.log').match(/https:\/\/.*trycloudflare\.com/)[0]
  end

  def stop
    Process.kill('TERM', @tunnel_pid)
  end

  attr_reader :public_url
end
```

**User experience**:
```bash
# Enable tunnel in config
# shortbus.yml:
# tunnel:
#   adapter: cloudflare
#   expose_blockqueue: true

shortbus run --tunnel
# Output:
# ✓ shortbus started
# ✓ BlockQueue started (localhost:8080)
# ✓ Cloudflare tunnel started
#   Public URL: https://abc-xyz-123.trycloudflare.com
#   Share this URL with remote services
```

### 6.3 Tunnel Use Cases

1. **POS/Edge**: Expose BlockQueue HTTP API for cloud integration
2. **Development**: Share local shortbus with remote team
3. **Webhooks**: Receive webhooks from cloud services (Stripe, Twilio)
4. **Remote monitoring**: Access BlockQueue metrics/health from HQ
5. **Hybrid cloud**: Local shortbus + remote subscribers via tunnel

**Security**:
- Cloudflare Tunnel: Encrypted by default (TLS)
- ngrok: Requires auth token, can add IP whitelist
- shortbus: Can add middleware (API keys, OAuth)

---

## 7. Implementation Strategy

### 7.1 Phase 1: Proof of Concept (1 week)

**Goal**: Validate wrapper architecture works

**Tasks**:
1. Deploy BlockQueue standalone (test Turso backend)
2. Build minimal Ruby wrapper:
   - Spawn BlockQueue process
   - HTTP client for publish/subscribe
   - Unix socket server (echo server)
3. Benchmark: Wrapper overhead vs direct BlockQueue

**Deliverable**: Working prototype, performance data

### 7.2 Phase 2: Core Features (2-3 weeks)

**Goal**: Feature-complete shortbus wrapper

**Tasks**:
1. **Process management**: Spawn, supervise, restart BlockQueue
2. **Unix socket IPC**: Full protocol implementation
3. **File watching**: inotify/fswatch for reactive notifications
4. **Trigger files**: Touch on publish, watch for changes
5. **Rendezvous directory**: Setup, discovery, PID files
6. **Config management**: shortbus.yml → blockqueue.yml generation
7. **CLI**: `shortbus run`, `publish`, `subscribe`, `console`

**Deliverable**: MVP shortbus wrapper

### 7.3 Phase 3: Polish (1-2 weeks)

**Goal**: Production-ready

**Tasks**:
1. **Tunnel adapters**: Cloudflare, ngrok support
2. **Error handling**: Graceful shutdown, health checks
3. **Logging**: Structured logs, debug mode
4. **Documentation**: README, examples, tutorials
5. **Testing**: Unit tests, integration tests
6. **Packaging**: Gem or binary distribution

**Deliverable**: Production-ready v1.0

**Total Timeline**: 4-6 weeks (vs 6-11 weeks from scratch)

### 7.4 Phase 4: Optimization (optional)

**If wrapper becomes bottleneck**:
1. Profile Ruby wrapper (stackprof)
2. Identify hot paths
3. Options:
   - Optimize Ruby code
   - Rewrite specific components in Go
   - Embed BlockQueue as library (Go only)

**Most likely**: Not needed (wrapper is thin)

---

## 8. Code Examples

### 8.1 Ruby Wrapper (Simplified)

```ruby
# lib/shortbus.rb
require 'socket'
require 'net/http'
require 'daemons'
require 'listen'

module Shortbus
  class Wrapper
    def initialize(rendezvous_dir)
      @rendezvous = Pathname.new(rendezvous_dir)
      @config = load_config
      @blockqueue_client = BlockQueueClient.new('http://localhost:8080')
    end

    def start
      # Start BlockQueue engine
      start_blockqueue

      # Start Unix socket server
      start_unix_socket

      # Start file watcher
      start_file_watcher

      puts "shortbus started"
      puts "  Unix socket: #{@rendezvous}/shortbus.sock"
      puts "  BlockQueue: http://localhost:8080"
    end

    private

    def start_blockqueue
      # Generate BlockQueue config from shortbus config
      generate_blockqueue_config

      # Spawn BlockQueue process
      @blockqueue_pid = Process.spawn(
        'blockqueue', '--config', @rendezvous / 'config/blockqueue.yml',
        out: @rendezvous / 'logs/blockqueue.log',
        err: @rendezvous / 'logs/blockqueue.err'
      )

      # Write PID file
      File.write(@rendezvous / 'blockqueue.pid', @blockqueue_pid)

      # Wait for BlockQueue to start
      wait_for_blockqueue
    end

    def start_unix_socket
      socket_path = @rendezvous / 'shortbus.sock'
      File.unlink(socket_path) if File.exist?(socket_path)

      @server = UNIXServer.new(socket_path)

      Thread.new do
        loop do
          client = @server.accept
          handle_client(client)
        end
      end
    end

    def handle_client(client)
      # Read length-prefix JSON
      length = client.read(4).unpack1('N')
      json = client.read(length)
      command = JSON.parse(json)

      case command['op']
      when 'publish'
        publish(command['topic'], command['payload'], command['metadata'])
        client.write([4, '{"status":"ok"}'.bytesize].pack('N') + '{"status":"ok"}')
      when 'subscribe'
        subscribe(command['topic'], client)
      end
    rescue => e
      client.write([4, "{\"error\":\"#{e.message}\"}".bytesize].pack('N') + "{\"error\":\"#{e.message}\"}")
    ensure
      client.close unless command['op'] == 'subscribe'
    end

    def publish(topic, payload, metadata = {})
      # HTTP POST to BlockQueue
      @blockqueue_client.publish(topic, payload, metadata)

      # Touch trigger file for reactive notifications
      trigger_file = @rendezvous / "topics/#{topic}.trigger"
      FileUtils.touch(trigger_file)
    end

    def subscribe(topic, client)
      # Register subscriber
      @subscribers ||= Hash.new { |h, k| h[k] = [] }
      @subscribers[topic] << client

      # Keep connection open for streaming
    end

    def start_file_watcher
      listener = Listen.to(@rendezvous / 'topics', only: /\.trigger$/) do |modified, added, removed|
        modified.each do |trigger_path|
          topic = File.basename(trigger_path, '.trigger')
          notify_subscribers(topic)
        end
      end

      listener.start
    end

    def notify_subscribers(topic)
      # Fetch new messages from BlockQueue
      messages = @blockqueue_client.fetch_messages(topic)

      # Stream to subscribers via Unix socket
      (@subscribers[topic] || []).each do |client|
        messages.each do |msg|
          json = msg.to_json
          client.write([4, json.bytesize].pack('N') + json)
        end
      end
    end
  end

  class BlockQueueClient
    def initialize(base_url)
      @base_url = URI(base_url)
    end

    def publish(topic, payload, metadata = {})
      uri = URI("#{@base_url}/topics/#{topic}/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      request.body = { payload: payload, metadata: metadata }.to_json
      response = http.request(request)
      JSON.parse(response.body)
    end

    def fetch_messages(topic, offset = 0)
      uri = URI("#{@base_url}/topics/#{topic}/messages?offset=#{offset}")
      response = Net::HTTP.get(uri)
      JSON.parse(response)['messages']
    end
  end
end
```

### 8.2 Go Wrapper (Simplified)

```go
// lib/shortbus/wrapper.go
package shortbus

import (
    "encoding/json"
    "net"
    "net/http"
    "os/exec"
    "github.com/fsnotify/fsnotify"
)

type Wrapper struct {
    rendezvous   string
    blockqueueCmd *exec.Cmd
    unixSocket    net.Listener
    httpClient    *http.Client
    subscribers   map[string][]net.Conn
}

func NewWrapper(rendezvousDir string) *Wrapper {
    return &Wrapper{
        rendezvous: rendezvousDir,
        httpClient: &http.Client{},
        subscribers: make(map[string][]net.Conn),
    }
}

func (w *Wrapper) Start() error {
    // Start BlockQueue engine
    if err := w.startBlockQueue(); err != nil {
        return err
    }

    // Start Unix socket server
    if err := w.startUnixSocket(); err != nil {
        return err
    }

    // Start file watcher
    go w.startFileWatcher()

    fmt.Println("shortbus started")
    return nil
}

func (w *Wrapper) startBlockQueue() error {
    // Generate BlockQueue config
    w.generateBlockQueueConfig()

    // Spawn BlockQueue process
    w.blockqueueCmd = exec.Command("blockqueue",
        "--config", filepath.Join(w.rendezvous, "config/blockqueue.yml"))

    if err := w.blockqueueCmd.Start(); err != nil {
        return err
    }

    // Wait for BlockQueue to start
    time.Sleep(2 * time.Second)
    return nil
}

func (w *Wrapper) startUnixSocket() error {
    socketPath := filepath.Join(w.rendezvous, "shortbus.sock")
    os.Remove(socketPath) // Clean up existing socket

    var err error
    w.unixSocket, err = net.Listen("unix", socketPath)
    if err != nil {
        return err
    }

    go w.acceptConnections()
    return nil
}

func (w *Wrapper) acceptConnections() {
    for {
        conn, err := w.unixSocket.Accept()
        if err != nil {
            continue
        }
        go w.handleClient(conn)
    }
}

func (w *Wrapper) handleClient(conn net.Conn) {
    // Read length-prefix JSON
    var length uint32
    binary.Read(conn, binary.BigEndian, &length)

    buf := make([]byte, length)
    io.ReadFull(conn, buf)

    var cmd Command
    json.Unmarshal(buf, &cmd)

    switch cmd.Op {
    case "publish":
        w.publish(cmd.Topic, cmd.Payload, cmd.Metadata)
        w.sendResponse(conn, map[string]string{"status": "ok"})
    case "subscribe":
        w.subscribe(cmd.Topic, conn)
    }
}

func (w *Wrapper) publish(topic string, payload, metadata map[string]interface{}) error {
    // HTTP POST to BlockQueue
    url := fmt.Sprintf("http://localhost:8080/topics/%s/messages", topic)
    body, _ := json.Marshal(map[string]interface{}{
        "payload": payload,
        "metadata": metadata,
    })

    resp, err := w.httpClient.Post(url, "application/json", bytes.NewBuffer(body))
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    // Touch trigger file
    triggerFile := filepath.Join(w.rendezvous, "topics", topic+".trigger")
    os.Chtimes(triggerFile, time.Now(), time.Now())

    return nil
}

func (w *Wrapper) subscribe(topic string, conn net.Conn) {
    w.subscribers[topic] = append(w.subscribers[topic], conn)
    // Keep connection open for streaming
}

func (w *Wrapper) startFileWatcher() {
    watcher, _ := fsnotify.NewWatcher()
    defer watcher.Close()

    watcher.Add(filepath.Join(w.rendezvous, "topics"))

    for {
        select {
        case event := <-watcher.Events:
            if event.Op&fsnotify.Write == fsnotify.Write {
                if strings.HasSuffix(event.Name, ".trigger") {
                    topic := strings.TrimSuffix(filepath.Base(event.Name), ".trigger")
                    w.notifySubscribers(topic)
                }
            }
        }
    }
}

func (w *Wrapper) notifySubscribers(topic string) {
    // Fetch new messages from BlockQueue
    messages := w.fetchMessages(topic)

    // Stream to subscribers
    for _, conn := range w.subscribers[topic] {
        for _, msg := range messages {
            w.sendResponse(conn, msg)
        }
    }
}
```

---

## 9. Risk Analysis

### 9.1 Risks

| Risk                             | Likelihood | Impact | Mitigation                              |
|----------------------------------|------------|--------|-----------------------------------------|
| BlockQueue API changes           | Low        | Medium | Pin BlockQueue version, integration tests |
| Wrapper overhead too high        | Low        | Medium | Benchmark early, optimize or use Go    |
| BlockQueue doesn't meet needs    | Medium     | High   | PoC first (week 1), evaluate before commit |
| File watching unreliable         | Low        | Medium | Trigger files proven pattern, test OSes |
| Unix socket portability          | Low        | Low    | Fallback to HTTP for Windows           |
| Dependency on BlockQueue project | Medium     | Medium | Could fork or swap engine later        |

### 9.2 Mitigation Strategies

**BlockQueue dependency**:
- ✅ **Apache 2.0 license**: Can fork if needed
- ✅ **Clean HTTP interface**: Easy to swap engines
- ✅ **Wrapper pattern**: Engine is replaceable

**Performance concerns**:
- ✅ **Benchmark first**: Week 1 PoC validates performance
- ✅ **Thin wrapper**: Minimal overhead (just IPC translation)
- ✅ **Go option**: Can rewrite wrapper if needed

**API stability**:
- ✅ **Pin BlockQueue version**: Don't auto-upgrade
- ✅ **Integration tests**: Detect breaking changes
- ✅ **Version compatibility matrix**: Document tested versions

---

## 10. Final Recommendation

### 10.1 The Verdict

**Build shortbus as a Ruby wrapper around BlockQueue.**

**Why**:
1. ✅ **Fastest time to MVP**: 4-6 weeks (vs 6-11 weeks from scratch)
2. ✅ **Leverages production code**: BlockQueue + Turso proven
3. ✅ **Preserves shortbus vision**: Filesystem, Unix sockets, file watching
4. ✅ **Author's expertise**: Ruby (from samples)
5. ✅ **Future-proof**: Can swap engine, rewrite wrapper later
6. ✅ **Clean architecture**: Separation of concerns (UX vs engine)

### 10.2 Implementation Plan

**Week 1: PoC**
- Deploy BlockQueue + Turso
- Build minimal Ruby wrapper (HTTP client + Unix socket echo)
- Benchmark: Validate wrapper overhead acceptable

**Week 2-3: Core Features**
- Process management (spawn BlockQueue)
- Full Unix socket protocol
- File watching + trigger files
- Rendezvous directory setup

**Week 4: CLI + Config**
- `shortbus run/stop/publish/subscribe`
- Config management (shortbus.yml → blockqueue.yml)
- Documentation

**Week 5-6: Polish**
- Tunnel adapters (Cloudflare, ngrok)
- Error handling, logging
- Testing, packaging

**Week 7+: Production**
- Load testing
- Edge case handling
- v1.0 release

### 10.3 Language Recommendation

**Primary: Ruby**
- Matches author's style
- 2-3 week faster development
- Perfect for facade/adapter pattern
- Wrapper overhead negligible

**Fallback: Go**
- If performance becomes issue (unlikely)
- If want static binary deployment
- If want to embed BlockQueue as library

**Most likely**: Ruby wrapper is sufficient, never need Go.

### 10.4 Success Criteria

**MVP Success** (Week 4):
- ✅ `git clone shortbus && cd shortbus && ./bin/shortbus run`
- ✅ Unix socket publish/subscribe works
- ✅ File watching triggers notifications
- ✅ Rendezvous directory self-contained
- ✅ BlockQueue managed automatically (user never sees it)

**Production Success** (Week 6):
- ✅ <5ms p99 latency (wrapper overhead)
- ✅ 10k+ msgs/sec throughput
- ✅ Tunnel adapters work (Cloudflare, ngrok)
- ✅ Documentation complete
- ✅ Tests passing

---

## Conclusion

**The wrapper architecture is brilliant because**:

1. **Composition over inheritance**: Classic design principle
2. **Separation of concerns**: UX (shortbus) vs engine (BlockQueue)
3. **Best of both worlds**: Turso performance + shortbus UX
4. **Rapid development**: Leverage existing code
5. **Future-proof**: Can swap engine later
6. **Proven pattern**: Docker, kubectl, AWS CLI all use this

**This is the right approach.** Build it.

---

**Document Author**: Claude (Anthropic)
**Based on**: Deep architectural analysis + research
**Date**: 2025-10-20
**Status**: Recommendation - ready for implementation
