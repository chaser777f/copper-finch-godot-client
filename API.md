# Client integration contract

Add `client/api/merchant_api.gd` as a Node, listen to `changed`, and render its
`state`, `config` and `status_text`. The example UI is in `client/main.gd`.
The client communicates through HTTP(S); it never imports Python or reads the server database.

Configure `configure_connection(url, username, password, allow_live)` and then
call `connect_session()`. Keep passwords in memory and use HTTPS remotely.

| Wrapper operation | HTTP route |
| --- | --- |
| Configuration check | `GET /v1/npc/config` |
| `connect_session()` — new | `POST /v1/merchant/sessions` with `{}` |
| Resume / `refresh_state()` | `GET /v1/merchant/sessions/{id}` |
| `talk(item, quantity, message)` | `POST /v1/merchant/sessions/{id}/decide` |
| `buy_offer()` / `reconcile_purchase()` | `POST /v1/merchant/sessions/{id}/purchases` |

Talk sends `item`, integer `quantity`, and `player_message`. Buy sends only
`request_id`, `offer_id`, `item`, and integer `quantity`. The server returns
catalog, prices, offers, stock, balances and receipts. Never invent a receipt,
infer a completed purchase from dialogue, or calculate a replacement price.

Hosted calls use tester HTTP Basic authentication plus the session capability
in `X-NPC-Session-Token`. Mutations include `X-NPC-Request: 1`. Compatible local
development servers use the session token in `Authorization: Bearer ...` with no
tester login. Local HTTP is allowed only for localhost; remote URLs require HTTPS.
These authentication contracts are already implemented by the wrapper.

The wrapper uses one request at a time, a timeout, a response size cap, no
redirects, and no automatic conversation retries. It persists the exact purchase
request before sending. If a response is uncertain, reconciliation reuses that
same request ID and body; a new ID could represent a new purchase.

A matching receipt is followed by a state refresh. Dialogue is plain text.
Original and served decisions, fallback statuses and dialogue diagnostics remain
visible. A quantity selector change does not modify an existing offer.

This document describes an interface, not a redistribution of its implementation.
The API backend, provider prompts and purchase implementation remain private.
