# Client-only release verification

This distribution excludes the backend and is tested against an isolated local
mock fixture of the existing hosted authentication contract. The fixture, its
credentials, and its database are private test tooling and are not included.

Checked on Windows with Godot **4.7.2.stable.steam.ed1daf0bf** using a freshly
extracted client-only ZIP. **25 assertions passed across two engine processes**
(17 initial-run assertions and 8 reopen assertions, including repeated startup
checks). These were actual headless Godot runs using the example scene's UI
callbacks and HTTPRequest wrapper, not graphical mouse interaction.

Confirmed:

- Empty server address, live opt-in off, no automatic connection, and disabled
  Talk/Buy/retry controls before explicit configuration.
- Explicit tester login against the local fixture, cleared password field,
  fresh session and locked controls during requests.
- Mock conversation creates an authoritative one-potion offer. Explicit Buy
  changes 100 gold / 0 player potions / 3 stock to 90 / 1 / 2.
- A new engine process and the same tester resume that session and purchase.
- A mocked moderation block leaves financial state unchanged and is displayed
  as an application status. Wrong passwords fail visibly.
- Separate tester profiles, no tester login credentials in the saved session file, rejection
  of remote plaintext HTTP and credentials embedded in URLs.

The ZIP audit checks its exact 13-file allowlist and verifies that every runtime
file matches the extracted copy tested above. No backend, launcher, SDK, model
prompt, database, credentials, test fixture or saved session is distributed.
All test-owned Godot processes and the local fixture were closed. No external
provider calls were made; the hosted shop was not contacted or changed.

The earlier combined package's 22 runtime checks are historical evidence, not a
claim that this client can run without a server. Hosted live availability, real
provider quality, other operating systems, and exported executables are not
verified by this release task. The backend's full test suite was not rerun:
backend code did not change. Pending-purchase network-failure tests and other
historical client tests were not repeated for this packaging-only update.
