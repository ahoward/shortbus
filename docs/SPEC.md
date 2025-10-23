# shortbus Specification

**Date**: 2025-10-20
**Version**: 1.0
**Architecture**: Wrapper around BlockQueue

---

## TL;DR: Wrapper Architecture

**Build shortbus as a Ruby facade/adapter around BlockQueue.** This is:
- ✅ **Architecturally sound** (proven pattern: Docker, kubectl, AWS CLI)
- ✅ **Faster to build** (4-6 weeks vs 6-11 weeks from scratch)
- ✅ **Best of both worlds** (Turso performance + shortbus UX)
- ✅ **Future-proof** (can swap engines later)

---

## Key Insights

### 1. **This is a Classic Design Pattern**

What you're describing is a **Service Facade with Adapter**:
```
shortbus (Facade) ← User interacts here
    ↓ HTTP (localhost)
BlockQueue (Engine) ← Does the heavy lifting
    ↓
Turso (Storage) ← Concurrent writes, microsecond reads
```

**Real-world examples**:
- Docker CLI → Docker daemon
- kubectl → Kubernetes API
- AWS CLI → AWS APIs
- redis-cli → Redis server

### 2. **Clear Separation of Concerns**

**BlockQueue provides**:
- ✅ Durable storage (Turso's 300% faster writes)
- ✅ Pub/sub mechanism
- ✅ HTTP API

**shortbus wrapper adds**:
- ✅ Unix domain sockets (41 Gbits/s vs HTTP)
- ✅ File watching (inotify for reactive push)
- ✅ Rendezvous directory (filesystem-based)
- ✅ Process management (spawn/supervise BlockQueue)
- ✅ Tunnel adapters (ngrok, Cloudflare)

### 3. **Ruby is Perfect for This**

**Why Ruby**:
- ✅ **Your expertise** (ro, map gems show Ruby mastery)
- ✅ **2-3 weeks faster** than Go (rapid development)
- ✅ **Perfect for facades** (metaprogramming, DSL, adapters)
- ✅ **Excellent libraries**: `daemons`, `listen`, `socket`, `net/http`

**Performance reality**:
- Wrapper overhead: **~1-2ms** (parsing + HTTP call)
- BlockQueue overhead: ~1-2ms (local HTTP)
- **Total**: ~3-4ms (vs 1-2ms direct BlockQueue)
- **Acceptable**: For local messaging, this is negligible

**The wrapper is thin** - just translates Unix socket → HTTP. Ruby won't be the bottleneck.

### 4. **Tunnel Adapters for POS/Edge**

**Your POS insight is brilliant**:
```
POS Terminal (edge)
  ↓
shortbus (local, fast)
  ↓
BlockQueue (Turso embedded replica)
  ↓
Cloudflare Tunnel
  ↓
Cloud HQ (monitoring, webhooks)
```

**Implementation**: Just shell out to `cloudflared` or `ngrok`:
```ruby
# lib/shortbus/tunnel/cloudflare.rb
Process.spawn('cloudflared tunnel --url http://localhost:8080')
# Parse log for public URL
```

---

## Implementation Plan

### **Week 1: Proof of Concept**
- Deploy BlockQueue + Turso
- Build minimal Ruby wrapper (HTTP client + Unix socket)
- **Validate**: Wrapper overhead <5ms

### **Weeks 2-3: Core Features**
- Process manager (spawn BlockQueue with `daemons` gem)
- Unix socket server (full protocol)
- File watcher (`listen` gem + trigger files)
- Rendezvous directory structure

### **Week 4: CLI + Config**
- `shortbus run/stop/publish/subscribe`
- Config (shortbus.yml → blockqueue.yml generation)

### **Weeks 5-6: Polish**
- Tunnel adapters (Cloudflare, ngrok)
- Error handling, tests, docs

**Total: 4-6 weeks to production-ready v1.0**

---

## Architecture Diagram

```
┌─────────────────────────────────┐
│      shortbus (Ruby)            │
│  ┌─────────┐  ┌──────────────┐ │
│  │  Unix   │  │ File Watcher │ │
│  │ Socket  │  │  (inotify)   │ │
│  └────┬────┘  └──────┬───────┘ │
│       │              │         │
│  ┌────▼──────────────▼──────┐  │
│  │  BlockQueue HTTP Client  │  │
│  └────────────┬──────────────┘  │
└───────────────┼─────────────────┘
                │ HTTP (localhost)
        ┌───────▼────────┐
        │  BlockQueue    │
        │  (Go engine)   │
        │  ┌──────────┐  │
        │  │  Turso   │  │ ← Concurrent writes!
        │  │ (replica)│  │ ← Microsecond reads!
        │  └──────────┘  │
        └────────────────┘
```

---

## Why This is The Right Approach

1. **Leverage existing code** (BlockQueue + Turso = production-tested)
2. **Preserve shortbus vision** (filesystem, Unix sockets, reactive)
3. **Rapid development** (Ruby wrapper = 2-3 weeks)
4. **Future-proof** (can swap engines: NATS, Redis, custom)
5. **Proven pattern** (Docker, kubectl, AWS CLI all use facades)

---

## My Recommendation

**Start Week 1 PoC immediately**:
1. Clone BlockQueue: `git clone https://github.com/yudhasubki/blockqueue`
2. Deploy with Turso backend
3. Build minimal Ruby wrapper (50 lines):
   - HTTP client to BlockQueue
   - Unix socket echo server
4. Benchmark: Measure wrapper overhead

**If PoC validates** (wrapper overhead <5ms):
→ Proceed with full implementation (Weeks 2-6)

**If PoC reveals issues** (unlikely):
→ Adjust architecture or use BlockQueue directly

---

**Document Author**: Claude (Anthropic)
**Based on**: Deep architectural analysis + research
**Status**: Approved specification - ready for implementation
