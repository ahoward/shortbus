# shortbus Client Examples

These examples demonstrate how to integrate with shortbus from different languages using **pipe mode**.

## Why Pipe Mode?

Pipe mode uses JSONL (JSON Lines) over stdin/stdout for bidirectional communication. This is:
- **Fast**: No HTTP overhead, direct pipe communication
- **Simple**: Standard input/output, works in any language
- **Universal**: JavaScript, Python, Go, Ruby, etc. - all work the same way
- **Non-blocking**: Read messages in background thread, write commands anytime

## Protocol

### Commands (write to stdin)

All commands are JSON objects, one per line:

```json
{"op": "publish", "topic": "events", "payload": "hello world"}
{"op": "subscribe", "topic": "events"}
{"op": "unsubscribe", "topic": "events"}
{"op": "ping"}
{"op": "shutdown"}
```

### Responses (read from stdout)

All responses are JSON objects, one per line:

```json
{"status": "ok", "op": "published", "message_id": 123, "request_id": 1}
{"type": "message", "topic": "events", "payload": "hello", "id": 123}
{"type": "error", "error": "something went wrong"}
```

## JavaScript Example

```bash
npm install  # no dependencies!
node client.js
```

```javascript
const { spawn } = require('child_process');

const shortbus = spawn('shortbus', ['pipe']);

// Read messages
shortbus.stdout.on('data', (data) => {
  const lines = data.toString().split('\n');
  lines.forEach(line => {
    if (!line) return;
    const msg = JSON.parse(line);
    console.log('Received:', msg);
  });
});

// Send commands
shortbus.stdin.write(JSON.stringify({
  op: 'publish',
  topic: 'events',
  payload: 'Hello from JS!'
}) + '\n');
```

See [client.js](./client.js) for full implementation.

## Python Example

```bash
python3 client.py
```

```python
import subprocess
import json

proc = subprocess.Popen(
    ['shortbus', 'pipe'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True
)

# Read messages (in background thread)
def read_messages():
    for line in proc.stdout:
        msg = json.loads(line)
        print('Received:', msg)

# Send commands
command = json.dumps({
    'op': 'publish',
    'topic': 'events',
    'payload': 'Hello from Python!'
}) + '\n'
proc.stdin.write(command)
proc.stdin.flush()
```

See [client.py](./client.py) for full implementation.

## Go Example

```bash
go run client.go
```

```go
cmd := exec.Command("shortbus", "pipe")

stdin, _ := cmd.StdinPipe()
stdout, _ := cmd.StdoutPipe()

cmd.Start()

// Read messages (in goroutine)
go func() {
    scanner := bufio.NewScanner(stdout)
    for scanner.Scan() {
        var msg map[string]interface{}
        json.Unmarshal(scanner.Bytes(), &msg)
        fmt.Println("Received:", msg)
    }
}()

// Send commands
command := map[string]interface{}{
    "op": "publish",
    "topic": "events",
    "payload": "Hello from Go!",
}
data, _ := json.Marshal(command)
stdin.Write(append(data, '\n'))
```

See [client.go](./client.go) for full implementation.

## Performance

Pipe mode is **significantly faster** than shelling out:

- **Shelling out**: ~10-50ms per command (process spawn overhead)
- **Pipe mode**: ~1-2ms per command (single process, reuse connection)

For high-throughput applications, this makes a **10-50x difference**.

## Features

All examples support:
- ✅ Publish messages
- ✅ Subscribe to topics
- ✅ Receive messages in real-time
- ✅ Request/response correlation (request_id)
- ✅ Error handling
- ✅ Graceful shutdown
- ✅ Concurrent operations

## Integration Tips

### 1. Keep Connection Open

Don't spawn a new process for each operation. Keep the pipe open and reuse it:

```javascript
// ❌ Bad: Spawn per operation (slow)
function publish(topic, msg) {
  const proc = spawn('shortbus', ['pipe']);
  // ...
}

// ✅ Good: Reuse connection (fast)
const bus = new ShortbusClient();  // Once
bus.publish(topic, msg);           // Many times
```

### 2. Background Thread for Reading

Always read stdout in a background thread/goroutine/async:

```python
# Background thread reads messages
threading.Thread(target=read_messages, daemon=True).start()

# Main thread sends commands
send_command(...)
```

### 3. Request ID Correlation

Use request_id to match responses to requests:

```javascript
const requestId = ++requestCounter;
const command = { op: 'publish', request_id: requestId, ... };

callbacks[requestId] = (response) => {
  console.log('Got response for request', requestId);
};
```

### 4. Error Handling

Always handle `type: "error"` responses:

```json
{"type": "error", "error": "topic not found", "command": {...}}
```

## Comparison: Pipe Mode vs HTTP vs Unix Socket

| Method      | Latency | Setup       | Language Support | Use Case           |
|-------------|---------|-------------|------------------|--------------------|
| Pipe Mode   | ~1-2ms  | spawn once  | All languages    | **Recommended**    |
| Unix Socket | ~1-2ms  | connect     | Most languages   | Same-machine only  |
| HTTP        | ~5-10ms | HTTP client | All languages    | Remote access      |

**Pipe mode is the sweet spot**: Fast, simple, universal.

## Next Steps

1. Copy example for your language
2. Modify to fit your use case
3. Run `shortbus pipe` in production
4. Integrate into your application

---

**This is the Unix way.** 🚀
