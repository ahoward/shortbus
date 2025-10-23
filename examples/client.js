#!/usr/bin/env node
//
// JavaScript client for shortbus using pipe mode
// Fast, simple, no dependencies
//

const { spawn } = require('child_process');
const readline = require('readline');

class ShortbusClient {
  constructor() {
    this.process = spawn('shortbus', ['pipe']);
    this.requestId = 0;
    this.callbacks = new Map();
    this.messageHandlers = new Map();

    // Setup line reader for JSONL
    const rl = readline.createInterface({
      input: this.process.stdout,
      crlfDelay: Infinity
    });

    rl.on('line', (line) => {
      try {
        const data = JSON.parse(line);
        this.handleResponse(data);
      } catch (e) {
        console.error('Parse error:', e.message);
      }
    });

    this.process.stderr.on('data', (data) => {
      console.error('shortbus:', data.toString());
    });

    this.process.on('exit', (code) => {
      console.log('shortbus exited:', code);
    });
  }

  handleResponse(data) {
    // Handle messages
    if (data.type === 'message') {
      const handlers = this.messageHandlers.get(data.topic) || [];
      handlers.forEach(handler => handler(data));
      return;
    }

    // Handle request/response
    if (data.request_id !== undefined) {
      const callback = this.callbacks.get(data.request_id);
      if (callback) {
        callback(data);
        this.callbacks.delete(data.request_id);
      }
    }

    // Handle errors
    if (data.type === 'error') {
      console.error('Error:', data.error);
    }
  }

  send(command, callback) {
    const requestId = ++this.requestId;
    command.request_id = requestId;

    if (callback) {
      this.callbacks.set(requestId, callback);
    }

    const line = JSON.stringify(command) + '\n';
    this.process.stdin.write(line);

    return requestId;
  }

  publish(topic, payload, metadata = {}) {
    return new Promise((resolve, reject) => {
      this.send({
        op: 'publish',
        topic,
        payload,
        metadata
      }, (response) => {
        if (response.status === 'ok') {
          resolve(response);
        } else {
          reject(new Error(response.error || 'Publish failed'));
        }
      });
    });
  }

  subscribe(topic, handler) {
    // Store message handler
    if (!this.messageHandlers.has(topic)) {
      this.messageHandlers.set(topic, []);
    }
    this.messageHandlers.get(topic).push(handler);

    // Send subscribe command
    return new Promise((resolve, reject) => {
      this.send({
        op: 'subscribe',
        topic
      }, (response) => {
        if (response.status === 'ok') {
          resolve(response);
        } else {
          reject(new Error(response.error || 'Subscribe failed'));
        }
      });
    });
  }

  unsubscribe(topic) {
    this.messageHandlers.delete(topic);

    return new Promise((resolve, reject) => {
      this.send({
        op: 'unsubscribe',
        topic
      }, (response) => {
        if (response.status === 'ok') {
          resolve(response);
        } else {
          reject(new Error(response.error || 'Unsubscribe failed'));
        }
      });
    });
  }

  ping() {
    return new Promise((resolve, reject) => {
      this.send({
        op: 'ping'
      }, (response) => {
        if (response.status === 'ok') {
          resolve(response);
        } else {
          reject(new Error('Ping failed'));
        }
      });
    });
  }

  shutdown() {
    this.send({ op: 'shutdown' });
    this.process.stdin.end();
  }
}

// Example usage
async function main() {
  const bus = new ShortbusClient();

  // Wait for ready
  await new Promise(resolve => setTimeout(resolve, 100));

  // Ping
  console.log('Ping:', await bus.ping());

  // Subscribe to events
  await bus.subscribe('events', (msg) => {
    console.log('Received:', msg.topic, msg.payload);
  });

  // Publish some messages
  await bus.publish('events', 'Hello from JavaScript!');
  await bus.publish('events', JSON.stringify({ user: 'alice', action: 'login' }));

  // Keep alive for a bit
  setTimeout(() => {
    bus.shutdown();
  }, 2000);
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = ShortbusClient;
