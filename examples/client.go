package main

// Go client for shortbus using pipe mode
// Fast, simple, concurrent

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"sync"
	"time"
)

type ShortbusClient struct {
	cmd            *exec.Cmd
	stdin          io.WriteCloser
	stdout         io.ReadCloser
	requestID      int
	callbacks      map[int]chan Response
	messageHandlers map[string][]MessageHandler
	mu             sync.Mutex
	running        bool
}

type Response struct {
	Type      string                 `json:"type,omitempty"`
	Status    string                 `json:"status,omitempty"`
	Op        string                 `json:"op,omitempty"`
	Topic     string                 `json:"topic,omitempty"`
	MessageID interface{}            `json:"message_id,omitempty"`
	Error     string                 `json:"error,omitempty"`
	RequestID int                    `json:"request_id,omitempty"`
	Payload   string                 `json:"payload,omitempty"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
	ID        int                    `json:"id,omitempty"`
	Timestamp int64                  `json:"timestamp,omitempty"`
}

type MessageHandler func(msg Response)

func NewClient() (*ShortbusClient, error) {
	cmd := exec.Command("shortbus", "pipe")

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}

	if err := cmd.Start(); err != nil {
		return nil, err
	}

	client := &ShortbusClient{
		cmd:             cmd,
		stdin:           stdin,
		stdout:          stdout,
		callbacks:       make(map[int]chan Response),
		messageHandlers: make(map[string][]MessageHandler),
		running:         true,
	}

	// Start response reader
	go client.readResponses()

	return client, nil
}

func (c *ShortbusClient) readResponses() {
	scanner := bufio.NewScanner(c.stdout)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var response Response
		if err := json.Unmarshal([]byte(line), &response); err != nil {
			fmt.Printf("Parse error: %v\n", err)
			continue
		}

		c.handleResponse(response)
	}

	c.running = false
}

func (c *ShortbusClient) handleResponse(response Response) {
	// Handle messages
	if response.Type == "message" {
		c.mu.Lock()
		handlers := c.messageHandlers[response.Topic]
		c.mu.Unlock()

		for _, handler := range handlers {
			go handler(response)
		}
		return
	}

	// Handle request/response
	if response.RequestID > 0 {
		c.mu.Lock()
		ch, ok := c.callbacks[response.RequestID]
		if ok {
			delete(c.callbacks, response.RequestID)
		}
		c.mu.Unlock()

		if ok {
			select {
			case ch <- response:
			case <-time.After(100 * time.Millisecond):
				// Timeout sending to channel
			}
		}
	}

	// Handle errors
	if response.Type == "error" {
		fmt.Printf("Error: %s\n", response.Error)
	}
}

func (c *ShortbusClient) send(command map[string]interface{}) (Response, error) {
	c.mu.Lock()
	c.requestID++
	requestID := c.requestID
	command["request_id"] = requestID

	ch := make(chan Response, 1)
	c.callbacks[requestID] = ch
	c.mu.Unlock()

	data, err := json.Marshal(command)
	if err != nil {
		return Response{}, err
	}

	if _, err := c.stdin.Write(append(data, '\n')); err != nil {
		return Response{}, err
	}

	select {
	case response := <-ch:
		return response, nil
	case <-time.After(5 * time.Second):
		c.mu.Lock()
		delete(c.callbacks, requestID)
		c.mu.Unlock()
		return Response{}, fmt.Errorf("timeout")
	}
}

func (c *ShortbusClient) Publish(topic, payload string, metadata map[string]interface{}) (Response, error) {
	if metadata == nil {
		metadata = make(map[string]interface{})
	}

	response, err := c.send(map[string]interface{}{
		"op":       "publish",
		"topic":    topic,
		"payload":  payload,
		"metadata": metadata,
	})

	if err != nil {
		return response, err
	}

	if response.Status != "ok" {
		return response, fmt.Errorf("publish failed: %s", response.Error)
	}

	return response, nil
}

func (c *ShortbusClient) Subscribe(topic string, handler MessageHandler) (Response, error) {
	c.mu.Lock()
	c.messageHandlers[topic] = append(c.messageHandlers[topic], handler)
	c.mu.Unlock()

	response, err := c.send(map[string]interface{}{
		"op":    "subscribe",
		"topic": topic,
	})

	if err != nil {
		return response, err
	}

	if response.Status != "ok" {
		return response, fmt.Errorf("subscribe failed: %s", response.Error)
	}

	return response, nil
}

func (c *ShortbusClient) Unsubscribe(topic string) (Response, error) {
	c.mu.Lock()
	delete(c.messageHandlers, topic)
	c.mu.Unlock()

	return c.send(map[string]interface{}{
		"op":    "unsubscribe",
		"topic": topic,
	})
}

func (c *ShortbusClient) Ping() (Response, error) {
	return c.send(map[string]interface{}{
		"op": "ping",
	})
}

func (c *ShortbusClient) Shutdown() {
	c.send(map[string]interface{}{
		"op": "shutdown",
	})
	c.stdin.Close()
	c.running = false
}

func main() {
	// Example usage
	client, err := NewClient()
	if err != nil {
		panic(err)
	}

	// Wait for ready
	time.Sleep(100 * time.Millisecond)

	// Ping
	resp, err := client.Ping()
	if err != nil {
		panic(err)
	}
	fmt.Printf("Ping: %+v\n", resp)

	// Subscribe to events
	client.Subscribe("events", func(msg Response) {
		fmt.Printf("Received: %s %s\n", msg.Topic, msg.Payload)
	})

	// Publish some messages
	client.Publish("events", "Hello from Go!", nil)
	client.Publish("events", `{"user":"charlie","action":"purchase"}`, nil)

	// Keep alive for a bit
	time.Sleep(2 * time.Second)

	client.Shutdown()
}
