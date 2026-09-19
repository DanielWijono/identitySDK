# Demo HTTP server

This loopback-only server exercises `HTTPVerificationProvider` through a real `URLSession` socket.
It deliberately has its own Python JSON models instead of importing the Swift `Wire` codec, so a
passing integration test provides evidence that the client and server agree on the wire contract.
It is a simulation and makes no identity decision.

Start it with:

```sh
python3 Examples/DemoHTTPServer/server.py --port 8080
```

The first stdout line reports the selected base URL as JSON. Pass `--port 0` to select an available
ephemeral port. `POST /sessions` is the host-side session-creation route; its JSON body accepts
`scenario` (`approve`, `reject`, `hold`, or `approveAfterPolls`), `lifetimeSeconds`, and optionally
`approveAfterPolls`.

For local TLS testing, pass both `--tls-cert` and `--tls-key`. The client continues to use normal
platform trust validation: an untrusted self-signed certificate is rejected rather than bypassed.
The automated suite uses plain HTTP over the loopback interface so it does not modify the machine's
trust store.

`--lose-submission-response-once` applies the first submission and closes its connection before
sending a response. This reproduces the ambiguous commit case against a real network transport.
The `GET /__test__/stats` endpoint exists only for local contract tests; do not deploy this server.
