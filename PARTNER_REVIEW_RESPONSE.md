# Response to your technical and security review

Thank you for the depth of the review — every observation in it is materially correct, and we
answer all eight below. First, your two governing conditions:

- **No Zyfai key may act alone.** Accepted. Anything shared moves behind a 2-of-2 Safe with
  you; after the final handover, Zyfai retains no ownership power over your stack at all. The
  only Zyfai-side authority that remains is the agent session key, whose exact, on-chain scope
  is specified in point 7 and is revocable by your Safe at any time.
- **Every safety property verifiable on-chain.** Accepted. Each commitment below states the
  on-chain check that proves it. We do not ask you to take anything on trust.

Addresses referenced throughout (Base):

| Contract | Address |
|---|---|
| TargetRegistry | `0xE23791a655Ad7707DB955d3a86f5e4e647799D95` |
| GuardedExecModule proxy | `0x9d7d5F76d8f529e4dDcDF7aC62e11A36e516BE17` |
| Adapter proxy | `0x4439eF06551D0580B4ebc5c2a2AB87cF4C1F9c64` |
| Adapter beacon | `0x0b7367de36Bc208E0A223fE5dCDcb89645c4E002` |

---

## 1. Ownership of all four contracts

Correct on both counts: all four are owned by a single deployer wallet today, and our transfer
script covered only the registry and the module. We have fixed the script: it now transfers
**all four contracts** in one run (`script/4-TransferPartnerOwnership.s.sol`).

Mechanics, per contract:

- **Registry, module, adapter** are `Ownable2Step`: we initiate, ownership only moves when
  your Safe calls `acceptOwnership()`. No transfer can land at a wrong address.
- **The beacon** is a plain `Ownable` (as you noted): its transfer is one-step and effective
  immediately at broadcast. The script asserts, before broadcasting, that the beacon is really
  the one behind the adapter proxy (EIP-1967 beacon slot) and that the deployer owns all four.

We will run the transfer to the Safe address you give us as soon as you confirm it.

**Verify on-chain:** `owner()` and `pendingOwner()` on registry, module and adapter;
`owner()` on the beacon. After your `acceptOwnership()` calls: `owner()` returns your Safe and
`pendingOwner()` returns zero on all three 2-step contracts.

## 2. No unilateral Zyfai control

Your observation is accurate. Between Sep 29 and Oct 11 the deployer key pointed the beacon at
the current Adapter release (the same code line as our shared production adapter — the upgrade
adds Makina support, see point 8) and staged Makina venue entries on this instance as part of
our integration testing. The changes themselves are benign, but your conclusion stands: while
the stack is pre-handover, a single Zyfai key can change your execution rails, and that is
exactly what must end before you fund anything.

**Commitment:** ownership of all four contracts moves out of single-key control before any
funding — either directly to your Safe (point 1) or, for any interim period you want us to
retain a role, to a 2-of-2 Safe whose signers are one Zyfai key and one key of yours. No
retained standalone-key power, on any of the four.

**Verify on-chain:** immediately before funding, re-read `implementation()` on the beacon,
`owner()` on all four contracts, and `pendingOwner()` on the three 2-step contracts (must be
zero — no transfer you did not initiate is in flight).

## 3. IntentExecutor

Confirmed: **the agent operates through the GuardedExec module alone.** The submission path
for your accounts is:

1. The agent builds the batch of calls (adapter deposits/redeems, token approvals).
2. It wraps them in a single `executeGuardedBatch` call on **your** module — the module
   validates every inner call against **your** TargetRegistry on-chain and reverts on anything
   not whitelisted.
3. It signs an ERC-4337 UserOperation with its session key under the SmartSessions validator
   (exact session scope in point 7) and submits it through a public bundler (Pimlico).

No other executor is involved. The IntentExecutor and the Emissary you found on the test
account belong to our retail cross-chain product (Rhinestone intents); the test account
received them because it went through our standard retail onboarding. They are not required
for the dedicated setup: in our backend, accounts without the emissary session never take the
intent path — they are routed to the bundler path above unconditionally.

**Commitment:** at deployment, the executor list on your accounts is exactly
`[your GuardedExecModule]`. We do not need the IntentExecutor, now or later. We acknowledge the
two code issues you found in it (expired instructions, gas-refund recipient); with the module
absent from your accounts, neither applies to you.

**Verify on-chain:** `getExecutorsPaginated` on the account returns only your module.

## 4. Emissary

What it is for: the Emissary validates our retail cross-chain intent flows — it produces the
ERC-7739/ERC-1271 account signatures that the Rhinestone spoke pool consumes. The two keys you
identified sign 2-of-2: one is a per-account agent session key held in Zyfai's signing
service, the other is a co-signing key held inside an EigenCloud TEE, so that no single Zyfai
service can produce a signature alone.

Your SudoPolicy analysis is nonetheless correct: an emissary permission carries a full
message-signing surface (ERC-1271), which is categorically more power than the agent needs on
your accounts — and we also acknowledge that uninstalling the module does not clear a
previously registered permission. It therefore simply does not belong on your accounts.

**Commitments:**

- No Emissary installed on your accounts, at deployment or later.
- Validators at deployment: exactly the owner validation controlled by your signers, plus the
  SmartSessions validator carrying the single permission specified in point 7. Nothing else.
- Module changes (install/uninstall of validators, executors, hooks) on a Safe7579 account
  require the **account owner's** signature — your Safe. The agent session cannot alter the
  module set: its only permitted action is `executeGuardedBatch` on your module, and your
  registry does not whitelist the account itself as a target.
- We share the exact account-deployment transaction with you for review before it runs.

**Verify on-chain:** `getValidatorsPaginated` and `getExecutorsPaginated` on the account match
the list above; the SmartSessions permission enumeration shows only the session in point 7.

## 5. Module checks recipients only on transfer/approve

Correct, and it is the intended design. The module is a (target, selector) firewall with two
special cases (ERC20 `transfer` recipients, `approve` spenders); it does not parse venue-call
arguments. Argument-level protection lives one layer down, in the **Adapter**: every
`*ForSelf` method hardcodes `msg.sender` — the smart account itself — as receiver/owner of
funds. There is no recipient or `onBehalfOf` parameter to abuse, which is verifiable in the
Adapter's published source on BaseScan.

Your corollary is the operating rule of this system: **safety equals allowlist content.** A
raw protocol endpoint with a free receiver argument must never be whitelisted — only the
Adapter's selectors, token `approve`/`transfer`, and venue approvals. That is precisely why
the registry moves to your ownership (point 1): the invariant is under your control, and every
venue proposal from us will route through the Adapter.

## 6. Approvals: uncapped, and they outlast pausing/removal

All three observations are correct, and we will not minimize them:

- The module never reads the `approve` amount. Some of our flows approve the exact operation
  amount, others grant unlimited allowance — you should treat any granted allowance as
  unbounded.
- Removing a spender from the allowlist stops future calls and approvals but does not clear an
  existing allowance.
- `removeFromWhitelist` is `whenNotPaused`, so pausing the registry blocks removals too.

What actually bounds the risk: an allowance is only exploitable by the spender contract
itself, and the only spenders ever whitelisted are your Adapter (whose code can only return
funds to the owning account, and whose upgrade key — the beacon — becomes yours per point 1)
and vault contracts you explicitly admitted. And the definitive kill switch sits above the
module entirely: your Safe, as the account owner, can revoke any allowance directly
(`approve(spender, 0)`) at any time, without touching module or registry.

If you want the pause semantics fixed (removals allowed while paused), we can patch and
redeploy your registry before handover — the stack is unfunded, so a redeploy costs nothing
but a new address. Your call.

## 7. Agent authority on your account

The exact session, verifiable on-chain after enablement:

| Field | Value |
|---|---|
| Validator | SmartSessions (canonical deployment) |
| Session signer | One per-account agent key held by Zyfai's signing service (address disclosed at deployment) |
| Allowed actions | Exactly one: target = your GuardedExecModule, selector = `executeGuardedBatch` (`0x2fc52d90`) |
| Action policy | SudoPolicy |
| UserOp policy | SudoPolicy |
| ERC-1271 / ERC-7739 surface | **None** — the session is userOp-only and cannot sign messages, so the permit / `transferWithAuthorization` drain path you described is closed |
| Expiry | None by default; the session is revocable instantly and unilaterally by your Safe (`removeSession`, or uninstalling the validator). We can attach a time-bound policy if you require bounded validity. |

On the SudoPolicy choice: it is deliberate. The restriction that matters is not expressible at
the policy layer — it is enforced by the module and your registry on every inner call of every
batch. The session merely says "the agent may knock on this one door"; the door decides.

Your note on `callPolicy` treating empty policy replies as approval is acknowledged; we use no
external call policies — only SudoPolicy — so nothing load-bearing sits on that code path.

On the test account: standard SmartSessions holds no permission there because that account's
authority ran through the Emissary + IntentExecutor (retail intent path). Your deployment uses
the SmartSessions path above instead, with neither of those modules installed.

## 8. Makina

Why it appeared: Makina is our next protocol integration (a USDC vault with queued
redemptions). The beacon upgrade you observed is the Adapter release that carries it
(`depositMakinaForSelf` / `requestMakinaRedeemForSelf`), and admitting the DirectDepositor and
AsyncRedeemer on this instance was part of our integration testing. Doing that on an instance
under your review, without notice, was a mistake on our side — fair criticism, and it is
exactly the class of change that stops being possible once point 1 is executed.

On the exit terms: your reading matches ours — redemptions finalize after a delay, a single
operational key performs finalization, and the delay parameter is changeable by their multisig
without a timelock. Whether that risk profile is acceptable for your funds is your decision,
not ours.

**Commitments:**

- The Makina entries staged during testing are removed before handover unless you tell us to
  keep them; your allowlist starts exactly where you want it.
- Every future venue proposal from us arrives as a written risk note plus the exact allowlist
  transaction, to be executed by your Safe — or not at all. We never admit a venue to your
  stack.

---

## Handover sequence

1. You send us your 2-of-2 Safe address.
2. We clean the test allowlist to the agreed venue set (point 8).
3. We run the four-contract transfer (point 1); the beacon moves immediately, you
   `acceptOwnership()` on registry, module and adapter.
4. You verify on-chain: `owner()` on all four = your Safe; `pendingOwner()` = zero;
   `implementation()` on the beacon is the reviewed Adapter release; `registry()` on the
   module = your registry.
5. We share the account-deployment transaction for review; after your sign-off, accounts are
   deployed with executors = [your module], validators = [owner validation, SmartSessions],
   and the single session of point 7. No Emissary, no IntentExecutor.
6. You fund.
