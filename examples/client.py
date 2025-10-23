#!/usr/bin/env python3
"""
Python client for shortbus using pipe mode
Fast, simple, no dependencies beyond standard library
"""

import json
import subprocess
import threading
import sys
from typing import Callable, Dict, Optional, Any


class ShortbusClient:
    def __init__(self):
        self.process = subprocess.Popen(
            ['shortbus', 'pipe'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1  # Line buffered
        )

        self.request_id = 0
        self.callbacks: Dict[int, Callable] = {}
        self.message_handlers: Dict[str, list] = {}
        self.running = True

        # Start reader thread
        self.reader_thread = threading.Thread(target=self._read_responses, daemon=True)
        self.reader_thread.start()

        # Start stderr reader
        self.stderr_thread = threading.Thread(target=self._read_stderr, daemon=True)
        self.stderr_thread.start()

    def _read_responses(self):
        """Read JSONL responses from stdout"""
        try:
            for line in self.process.stdout:
                line = line.strip()
                if not line:
                    continue

                try:
                    data = json.loads(line)
                    self._handle_response(data)
                except json.JSONDecodeError as e:
                    print(f'Parse error: {e}', file=sys.stderr)
        except Exception as e:
            print(f'Reader error: {e}', file=sys.stderr)
        finally:
            self.running = False

    def _read_stderr(self):
        """Read stderr output"""
        try:
            for line in self.process.stderr:
                print(f'shortbus: {line.strip()}', file=sys.stderr)
        except Exception:
            pass

    def _handle_response(self, data: Dict[str, Any]):
        """Handle a response from shortbus"""
        # Handle messages
        if data.get('type') == 'message':
            topic = data.get('topic')
            if topic in self.message_handlers:
                for handler in self.message_handlers[topic]:
                    try:
                        handler(data)
                    except Exception as e:
                        print(f'Handler error: {e}', file=sys.stderr)
            return

        # Handle request/response
        request_id = data.get('request_id')
        if request_id is not None and request_id in self.callbacks:
            callback = self.callbacks.pop(request_id)
            callback(data)

        # Handle errors
        if data.get('type') == 'error':
            print(f"Error: {data.get('error')}", file=sys.stderr)

    def _send(self, command: Dict[str, Any], callback: Optional[Callable] = None) -> int:
        """Send a command to shortbus"""
        self.request_id += 1
        command['request_id'] = self.request_id

        if callback:
            self.callbacks[self.request_id] = callback

        line = json.dumps(command) + '\n'
        self.process.stdin.write(line)
        self.process.stdin.flush()

        return self.request_id

    def publish(self, topic: str, payload: Any, metadata: Optional[Dict] = None) -> Dict[str, Any]:
        """Publish a message to a topic"""
        result = {}
        event = threading.Event()

        def callback(response):
            result.update(response)
            event.set()

        self._send({
            'op': 'publish',
            'topic': topic,
            'payload': payload,
            'metadata': metadata or {}
        }, callback)

        event.wait(timeout=5.0)

        if not result:
            raise TimeoutError('Publish timeout')

        if result.get('status') != 'ok':
            raise Exception(result.get('error', 'Publish failed'))

        return result

    def subscribe(self, topic: str, handler: Callable[[Dict], None]) -> Dict[str, Any]:
        """Subscribe to a topic"""
        # Store message handler
        if topic not in self.message_handlers:
            self.message_handlers[topic] = []
        self.message_handlers[topic].append(handler)

        result = {}
        event = threading.Event()

        def callback(response):
            result.update(response)
            event.set()

        self._send({
            'op': 'subscribe',
            'topic': topic
        }, callback)

        event.wait(timeout=5.0)

        if not result:
            raise TimeoutError('Subscribe timeout')

        if result.get('status') != 'ok':
            raise Exception(result.get('error', 'Subscribe failed'))

        return result

    def unsubscribe(self, topic: str) -> Dict[str, Any]:
        """Unsubscribe from a topic"""
        if topic in self.message_handlers:
            del self.message_handlers[topic]

        result = {}
        event = threading.Event()

        def callback(response):
            result.update(response)
            event.set()

        self._send({
            'op': 'unsubscribe',
            'topic': topic
        }, callback)

        event.wait(timeout=5.0)
        return result

    def ping(self) -> Dict[str, Any]:
        """Ping the bus"""
        result = {}
        event = threading.Event()

        def callback(response):
            result.update(response)
            event.set()

        self._send({'op': 'ping'}, callback)

        event.wait(timeout=5.0)

        if not result:
            raise TimeoutError('Ping timeout')

        return result

    def shutdown(self):
        """Shutdown the connection"""
        self._send({'op': 'shutdown'})
        self.process.stdin.close()
        self.running = False


def main():
    """Example usage"""
    import time

    bus = ShortbusClient()

    # Wait for ready
    time.sleep(0.1)

    # Ping
    print('Ping:', bus.ping())

    # Subscribe to events
    def on_message(msg):
        print(f"Received: {msg['topic']} {msg['payload']}")

    bus.subscribe('events', on_message)

    # Publish some messages
    bus.publish('events', 'Hello from Python!')
    bus.publish('events', json.dumps({'user': 'bob', 'action': 'logout'}))

    # Keep alive for a bit
    time.sleep(2)

    bus.shutdown()


if __name__ == '__main__':
    main()
