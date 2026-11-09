# Quitegood hbbs

Fork of [rustdesk/rustdesk-server](https://github.com/rustdesk/rustdesk-server) @ 680b603 (AGPL-3.0).

Change (src/rendezvous_server.rs): peers can register over TCP/WebSocket instead of UDP.
- `RegisterPk` on a TCP/WS connection is validated like the UDP path (`process_register_pk`),
  answered with `keep_alive=30`, and the connection is kept as the peer's channel.
- The server sends an empty heartbeat every 15 s; the client's echo refreshes `last_reg_time`.
- Messages for that peer (PunchHole, RequestRelay...) go through the connection instead of UDP.
- `OnlineRequest` is answered on the main TCP/WS listener (WebSocket clients send it there).

Needed for clients with `allow-websocket=Y` / UDP disabled behind a TLS proxy on 443.
