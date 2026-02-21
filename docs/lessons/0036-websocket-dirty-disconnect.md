---
id: 0036
title: "WebSocket dirty disconnects raise RuntimeError, not close"
severity: should-fix
languages: [python]
category: resource-lifecycle
pattern:
  type: semantic
  description: "WebSocket send after client disconnects without close frame raises RuntimeError instead of WebSocketDisconnect"
fix: "Wrap all WebSocket sends in try/except RuntimeError and clean up the connection"
example:
  bad: |
    async def broadcast(self, message):
        for ws in self.connections:
            await ws.send_json({"msg": message})
  good: |
    async def broadcast(self, message):
        for ws in self.connections:
            try:
                await ws.send_json({"msg": message})
            except RuntimeError:
                self.connections.remove(ws)
---

## Observation
WebSocket connections that are terminated by the client without a proper close frame (e.g., mobile network loss, browser tab close) raise `RuntimeError` on the next `send()` call, not `WebSocketDisconnect`. This exception type varies by websocket library implementation and client disconnection method.

## Insight
Developers expect WebSocket sends to raise `WebSocketDisconnect` on all disconnection types, so they only catch that exception. Dirty disconnects bypass the close handshake, triggering RuntimeError instead. This causes unhandled exceptions in broadcast loops.

## Lesson
Always wrap WebSocket sends in `try/except RuntimeError` in addition to connection-close handlers. Store connection state on `self`, remove failed connections immediately, and log the disconnection for visibility. Test with mobile network loss simulation, not just clean closes.
