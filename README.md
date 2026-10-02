# Copper Finch — Godot client example

A small **MIT-licensed Godot client** for the Copper Finch merchant API.
Talk to request an offer, review its item, quantity and price, then explicitly
choose **Buy**. The server owns the catalog, decisions, stock and purchases.

**This download is client-only.** You need access to a compatible server.
The Copper Finch hosted shop is invite-only: an individual tester login is
required, and no invitation is included in the download. Without server access
you can inspect and adapt the client, but cannot play the merchant interaction.
No Python installation or model API keys are needed on the player's computer.

Download [version 0.1.0](https://github.com/chaser777f/copper-finch-godot-client/releases/tag/v0.1.0)
and choose the `copper-finch-godot-client-0.1.0.zip` asset. The source and
[issue tracker](https://github.com/chaser777f/copper-finch-godot-client/issues)
are public; the hosted backend remains private and invite-only.

## Connect from Godot

1. Install [Godot 4.7.x standard](https://godotengine.org/download/). This example
   was tested with Godot 4.7.2 on Windows; the .NET build is not required.
2. Extract the ZIP. In Godot's Project Manager choose **Import**, select
   `client/project.godot`, and open it. Press **F5**.
3. The client starts disconnected. Enter the address provided with your
   invitation. The Copper Finch shop address is
   `https://npc-decision-lab.onrender.com`.
4. Enter your individual tester username and password. For a live AI server,
   tick **Allow this connection to use live AI providers**. Click
   **Connect with these settings**. Connecting and refreshing do not call models.
5. Check the displayed active decision/dialogue providers before talking.
   Choose an item and quantity, enter a message, and select **Talk to merchant**.
6. If an offer appears, review it and use **Buy** only when you want to accept.
   A purchase is confirmed only after the server returns its receipt.

The password field clears when connecting. Login stays in memory until the
client closes; it is not saved to the project or profile. Re-enter your login
after reopening. The same tester and server resume this client's saved session,
which is separate from the browser demo's session.

No server address is preconfigured and live-provider access is disabled by
default. The original development example's local mock mode is separate. This
package includes no mock server or offline AI. An existing compatible localhost
mock server can still be selected explicitly, with blank login fields and the
live checkbox left off.

## Availability and privacy

Hosted use requires internet, a working server and an authorized account. The
client cannot continue merchant transactions offline, and does not silently
switch to mock responses. Server outages, rate limits and moderation notices
are displayed as application errors/status, not merchant success. Conversation
requests are never automatically retried.

Live messages may be sent to external AI providers and checked for safety.
Do not send private information. Provider keys remain on the server. The
service's limits and access policy apply separately from this code's license.

## If something goes wrong

- **401:** check your tester login, not your Render login. Contact the invitation
  owner if your account is unavailable; never send them your password.
- **Connection failed:** check the address and availability. HTTPS is required
  for remote servers. Do not disable certificate checks.
- **Live providers blocked:** explicitly allow live providers and reconnect if
  that is the server you intend to use.
- **Uncertain purchase:** select **Check pending purchase**. It retains the same
  request ID so reconciliation cannot charge again under the API contract.
  Do not delete its profile or create a replacement purchase to work around it.
- **Application blocked/unavailable:** read the notice. Repeatedly resending a
  blocked message does not fix it.

Changing the quantity control affects the next requested offer; it does not
rewrite a quote already on the counter. Talking never buys an item.

## Integrate it

`client/api/merchant_api.gd` is a reusable Node wrapping Godot's `HTTPRequest`.
The example scene in `client/main.gd` handles presentation. See [API.md](API.md)
for the contract. The code can be adapted for your own commercial game under
[MIT](LICENSE); retain its copyright and license notice. See [NOTICE.md](NOTICE.md)
for the boundary between this client and the private hosted service.

The client stores session capabilities and pending purchase details in Godot's
user-data folder `CopperFinchClientExample` (Windows normally
`%APPDATA%\CopperFinchClientExample`). **Project > Open User Data Folder** shows
the location. Use one client per profile and preserve unresolved purchases.
Do not share this directory. Different tester identities have separate profiles.

## Optional feedback

Use the [issue tracker](https://github.com/chaser777f/copper-finch-godot-client/issues), or contact
the release maintainer. Include version, OS/Godot version, steps and the visible
error. Never attach passwords, keys, tokens, saved profiles, databases, or private
conversation history. [VERIFICATION.md](VERIFICATION.md) describes what was checked.

This is the 0.1.0 client-only release. It contains
no backend code, provider SDKs, model prompts, credentials, accounts or saved data.
