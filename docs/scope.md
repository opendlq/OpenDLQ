# Scope

What OpenDLQ will not do, and the design questions still open. What each version ships is in the [roadmap](../roadmap/README.md).

## Non-goals

- Replacing or implementing a message broker.
- Ordering of replays, globally or per partition key. A replay keeps its original partition key, not its original position. A consumer that depends on order checks a version or a timestamp.
- Deciding on its own how to fix a permanent failure.
- Replacing your logging or observability stack. OpenDLQ reads from it; it does not store logs.

## Open questions

- [ ] Default recovery detection: `ack` or `silence`?
- [ ] Canary: oldest held message or newest? The oldest has waited longest; the newest is more likely to still be valid.
- [ ] Payload edits before replay: JSON Patch or full replacement?
- [ ] Custom detectors: declared SQL, or a plugin?
