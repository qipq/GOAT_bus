https://github.com/qipq/GOAT_bus/releases

# GOAT_bus — Enterprise Event Bus for Game Design & Live Ops

[![Releases](https://img.shields.io/badge/Releases-download-blue?logo=github)](https://github.com/qipq/GOAT_bus/releases)

A production-ready event bus tailored for games. GOAT_bus handles persistent queues, event replay, pseudo-backpressure, and health-aware routing. It scales to match live game traffic. Download the release binary from the releases page above and execute it to run a node.

![Game event flow](https://images.unsplash.com/photo-1505740420928-5e560c06d30e?q=80&w=1400&auto=format&fit=crop)

Table of contents
- Features
- Design goals
- Quickstart (download and run)
- Core concepts
- Persistence & replay
- Routing & health-awareness
- Backpressure model
- API and client examples
- Deployment and ops
- Metrics and tracing
- Troubleshooting tips
- Contributing

Features
- Durable queues with ordered partitions.
- Event replay by offset and time range.
- Pseudo-backpressure to avoid overload without blocking producers.
- Health-aware routing: route events away from nodes under load or in degraded state.
- Acks and delivery guarantees configurable per topic.
- Pluggable storage backends (local WAL, S3, or networked store).
- Lightweight Go runtime with low GC footprint.
- Prometheus metrics and OpenTelemetry traces.

Design goals
- Predictable latency for game-critical events.
- Safe persistence to avoid lost state on crash.
- Fast replay for state recovery and debugging.
- Simple client API for game servers and tooling.

Quickstart — download and run
- Visit and download the release binary (the release file needs to be downloaded and executed): https://github.com/qipq/GOAT_bus/releases
- Pick the binary for your platform and extract it.
- Run the server:

```bash
# Example for Linux AMD64 release
wget https://github.com/qipq/GOAT_bus/releases/download/v1.2.0/goat_bus-linux-amd64.tar.gz
tar -xzf goat_bus-linux-amd64.tar.gz
./goat_bus server --config ./config.yaml
```

The downloaded release binary above is executable. Adjust the file name to match the release you picked from https://github.com/qipq/GOAT_bus/releases

Core concepts
- Broker: A running GOAT_bus node that accepts, stores, and forwards events.
- Topic: Logical stream of related events (e.g., player.actions).
- Partition: Ordered shard within a topic. A partition gives ordering and parallelism.
- Offset: Numeric marker of event position inside a partition.
- Durable log: The append-only store that holds events until retention or manual deletion.
- Subscriber: A client that consumes events from topic partitions.
- Publisher: A client that sends events into topics.

Persistence and event replay
- Append-only WAL: GOAT_bus appends events to a write-ahead log. This gives fast writes and safe recovery.
- Compaction: Optional compaction reduces storage for stateful topics.
- Retention: Configure retention by time or size per topic.
- Replay API: Pull events by offset range or by timestamp to rebuild state or test logic.

Example: replay last hour for partition 2
```bash
./goat_bus replay --topic player.state --partition 2 --since "1h"
```

Routing and health-awareness
- Health checks: Each broker exposes a health endpoint with load, latency, and disk metrics.
- Health-aware router: The router routes publish and subscription requests to the least-degraded nodes for the target partition.
- Sticky routing: For minimal client churn, routing keeps a stable mapping until health crosses thresholds.
- Failover: If a node fails, the router reassigns partitions and promotes replicas.

Health check JSON (example)
```json
{
  "uptime": 12400,
  "load": 0.45,
  "disk_free_pct": 32,
  "lag_ms": 12,
  "status": "healthy"
}
```

Pseudo-backpressure model
- Goal: Avoid producer overload while keeping producers non-blocking.
- Approach: Brokers return a soft accept code when under pressure. Clients can:
  - Slow send rate.
  - Buffer locally with bounded size.
  - Switch to alternate broker or queue.
- Token buckets: The server exposes tokens per partition. Clients throttle send rate based on tokens.
- Drop policies: Configurable per topic (oldest, newest, none).

API and client examples

HTTP publish (simple)
```bash
curl -X POST http://broker:8080/publish \
  -H "Content-Type: application/json" \
  -d '{"topic":"player.actions","partition":3,"payload":{"action":"jump","player":"abc"}}'
```

Go client (publish)
```go
package main

import (
  "context"
  "github.com/qipq/goat_bus/client"
  "time"
)

func main() {
  cli := client.New("http://broker:8080")
  ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
  defer cancel()
  err := cli.Publish(ctx, "player.actions", 1, []byte(`{"action":"shoot"}`))
  if err != nil {
    panic(err)
  }
}
```

Go client (consume)
```go
sub, _ := cli.Subscribe("player.actions", 1, client.FromOffset(0))
for ev := range sub.Events() {
  // ack when processed
  ev.Ack()
}
```

API semantics
- Publish returns a delivery receipt with partition and offset.
- Subscribe returns a stream with at-least-once delivery. Clients can request exactly-once semantics via dedupe keys.
- Ack protocols: explicit ack and auto-ack options.

Deployment and ops
- Single-broker mode for dev.
- Multi-broker mode with router for production.
- Replication factor: set per topic.
- Storage options:
  - Local WAL on SSD for lowest latency.
  - Network store for shared durability.
  - Offsite archive to S3 for long-term retention.
- Rolling upgrade: broker nodes drain then update to avoid downtime.
- Configuration: YAML or environment variables. Key fields:
  - network.bind
  - storage.path
  - replication.factor
  - partition.count
  - metrics.enabled

Example config.yaml
```yaml
network:
  bind: 0.0.0.0:8080

storage:
  path: /var/lib/goat_bus
  max_log_size_mb: 1024

replication:
  default: 3
```

Metrics and tracing
- Prometheus exporter on /metrics.
- Useful metrics:
  - goatbus_events_in_total
  - goatbus_events_out_total
  - goatbus_partition_lag
  - goatbus_disk_free_bytes
- Traces: OpenTelemetry spans tag publish and consume flows.
- Alert rules:
  - Partition lag > X ms for Y minutes.
  - Disk free < 20%.

Troubleshooting tips
- Check /health on the broker for live metrics.
- If replay fails, inspect WAL and compare offsets.
- If producers see backpressure codes, reduce send rate or add capacity.
- Use metrics to find hot partitions and rebalance as needed.

Architecture diagram
![Architecture](https://raw.githubusercontent.com/qipq/GOAT_bus/main/docs/images/architecture.svg)

Best practices for games
- Partition by player ID for consistency of player state.
- Use small partitions for highly parallel event types (telemetry).
- Use durable topics for match state and ephemeral topics for chat.
- Limit retention on chat topics to preserve storage.
- Play test replay paths in staging to validate recovery flows.

Security
- TLS for all broker traffic.
- Token-based authentication for clients.
- ACLs per topic with allow/deny rules.

CLI reference
- server: start a broker node.
- publish: send a single event from the shell.
- subscribe: listen to a topic partition.
- replay: replay stored events.
- admin: manage topics, partitions, and retention.

Example: create topic
```bash
./goat_bus admin create-topic --name match.state --partitions 8 --replicas 3
```

Contributing
- Fork the repo.
- Run unit tests and integration tests in ./test.
- Open a pull request with a clear description.
- Follow the style guide in CONTRIBUTING.md.

License
- MIT license. See LICENSE file.

Resources
- Releases and binaries: https://github.com/qipq/GOAT_bus/releases
- Docs: docs/ directory in the repo
- Example clients: clients/go, clients/js

Community
- Open issues for feature requests and bug reports.
- Use issues to propose new routing logic or storage adapters.
- Share replay scripts and test datasets under examples/.

End of file