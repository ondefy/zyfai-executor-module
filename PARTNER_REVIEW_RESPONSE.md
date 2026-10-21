# Your dedicated Base setup: answers to the review and deployment plan

Thank you for the review. It is accurate, and everything it asks for is doable. This document
does three things:

1. Summarizes what your deployment will look like, and how it differs from the test setup
   you reviewed.
2. Answers each of the eight points, with the on-chain check that proves each commitment.
3. Lists the few inputs we need from you to deploy.

We accept both of your conditions as stated:

- **No Zyfai key may act alone.** Your infrastructure is owned by a 2-of-2 Safe with one
  Zyfai signer and one of yours. Your smart account is owned by you alone.
- **Every safety property is verifiable on-chain.** Each point below states what to read and
  where. We do not ask you to rely on attestations.

---

## 1. Your deployment at a glance

The test stack you reviewed was assembled from our retail onboarding, so it carried retail
defaults. It is retired. You get a fresh deployment with new addresses.

| | Test setup you reviewed | Your deployment |
|---|---|---|
| Registry, module, adapter, beacon owner | One Zyfai deployer key | 2-of-2 Safe (Zyfai + you), on all four contracts |
| Executors on your account | GuardedExec + IntentExecutor | **GuardedExec only** (your module) |
| Validators on your account | Owner validator + SmartSessions + Emissary | **Owner validator + SmartSessions only**. No Emissary. |
| Agent authority | Emissary intent session (ERC-1271 signing) | **One SmartSessions session that can only call `executeGuardedBatch` on your module**. No message signing. |
| Execution path | Rhinestone intents | ERC-4337 UserOperation → SmartSessions → your module → your registry |
| Allowlist | Clearstar + staged Makina entries | **Only the IPOR vaults you designate** |
| Adapter code | Earlier release | Current audited release (see point 8) |

## 2. How the deployment will go

1. **2-of-2 Safe.** We create it together on Base with owners = [Zyfai signer, your signer]
   and threshold 2. You check `getOwners()` and `getThreshold()` before anything else.
2. **Deploy and configure.** We deploy your TargetRegistry, GuardedExec module, Adapter and
   Adapter beacon, then configure only the agreed IPOR vaults (section 4) on the Adapter and
   the registry.
3. **Ownership transfer to the Safe** for all four contracts. Registry, module and Adapter use
   `Ownable2Step`, so ownership only moves when the Safe calls `acceptOwnership()`, which
   needs both signatures. The beacon is a plain `Ownable` and moves in one step. Our script
   checks, before broadcasting, that it is the beacon actually behind your Adapter (via the
   EIP-1967 slot).
4. **You verify the infrastructure** (checklist in section 5) and then co-sign the three
   `acceptOwnership()` calls.
5. **Account deployment.** Your smart account is deployed by a single batch signed by **your**
   owner key. We send you the exact batch to review before you sign it. It contains:
   - Install the SmartSessions validator `0x00000000008bDABA73cD9815d79069c247Eb4bDA`.
   - Install your GuardedExec module as the only executor.
   - Enable the single agent session described in point 7. It is enabled inside the
     deployment batch, so it is live and readable on-chain before you fund.
   - Disable the account's ERC-7484 module-attestation check. Rhinestone has retired the
     attester these accounts were created with, so installing any non-attested module (your
     module included) would otherwise revert. Module installs remain gated by your owner
     signature.
6. **You verify the account** (section 5), then fund it.

---

## 3. Point-by-point answers

### Point 1: Ownership of all four contracts

You were right that our transfer script covered only the registry and the module. It now
transfers all four contracts (registry, module, Adapter and beacon) to the 2-of-2 Safe, as
described in step 3 above.

**Verify on-chain:** `owner()` returns the Safe on all four contracts, and `pendingOwner()`
returns `0x0` on the registry, module and Adapter.

### Point 2: No unilateral Zyfai control

Your reading is correct. Between Sep 29 and Oct 11 our deployer key re-pointed the test beacon
and admitted two Makina contracts, as part of our own integration testing (see point 8). The
changes were harmless, but they show that one key could change your rails. That is the
situation we are ending.

After the handover, every power over your infrastructure requires both signatures: allowlist
changes, pausing, Adapter venues, the module's UUPS upgrade, and the beacon upgrade. Neither
Zyfai nor you can act alone on it. Your smart account is not part of this shared perimeter:
it is owned by you only.

**Verify on-chain, right before funding:** re-read `implementation()` on the beacon (it must
be the reviewed release), the module's implementation slot, `owner()` on all four contracts,
and `pendingOwner()` on the three 2-step contracts. Any later change shows up as a Safe
transaction carrying both signatures.

### Point 3: IntentExecutor

**Confirmed: the agent operates through the GuardedExec module alone, and the IntentExecutor
is not required.** The submission path for your account is:

1. Our backend builds the batch: approvals plus Adapter `depositVaultForSelf` /
   `redeemVaultForSelf` calls.
2. It wraps the batch in one `executeGuardedBatch` call on your module. The module checks
   every inner call against your registry and reverts on anything that is not allowlisted.
3. It signs an ERC-4337 UserOperation under the session in point 7 and submits it through
   the Pimlico bundler, with gas sponsored by a paymaster.

Rhinestone intents are a retail cross-chain feature. Your account is Base-only, and our
backend will send it exclusively through the path above. The two IntentExecutor code issues you found (expired
instructions can still run, and the submitter picks the gas-refund recipient) do not apply to
you, because the module will not be installed.

**Verify on-chain:** the executor list on your account contains only your module.

### Point 4: Emissary

- **What it does.** The SmartSessionEmissary validates Rhinestone cross-chain intents for our
  retail users. It produces the account signatures that the Rhinestone settlement contracts
  consume.
- **Who holds the keys.** The two signers you identified (`0x8018…b030` and `0x8076…9b81`) are
  both Zyfai keys, and the session requires both signatures:
  - a session key held by our backend signing service;
  - a co-signing key held inside an EigenCloud TEE, so that no single Zyfai service can sign
    alone.
- **Why it doesn't belong on your account.** Your analysis is right. The Emissary permission
  carries a full ERC-1271 signing surface, which is more power than the agent needs. A
  registered permission also survives uninstalling the module. So the Emissary is never
  installed on your account, and no Emissary permission is ever registered for it.
- **Modules the agent needs.** These are the full list, with their roles:

  | Module | Type | Role |
  |---|---|---|
  | OwnableValidator (owner = your address, threshold 1) | Validator | Your owner authority: deployment, module changes, session revocation |
  | SmartSessions `0x00000000008bDABA73cD9815d79069c247Eb4bDA` | Validator | Carries the single agent session (point 7) |
  | Your GuardedExec module | Executor | Executes the agent's batches, checking each call against your registry |

  No other validator, executor, hook or fallback handler is installed.
- **Who can change modules.** On a Safe7579 account, installing or uninstalling modules
  requires the owner's signature, which is yours. The agent session cannot do it: its only
  allowed action is `executeGuardedBatch` on your module, and your registry does not allowlist
  the account itself as a target.

**Verify on-chain:** `getValidatorsPaginated` and `getExecutorsPaginated` on your account
return exactly the table above.

### Point 5: The module checks recipients only on `transfer` and `approve`

Correct, and this is by design. The module checks `(target, selector)` pairs and has only two
special cases: ERC20 `transfer` recipients and `approve` spenders. It does not parse venue
arguments.

Argument-level protection is in the Adapter. Every `*ForSelf` function hardcodes `msg.sender`,
which is your account, as the receiver and owner of the funds. There is no recipient or
`onBehalfOf` parameter that could be abused, and you can check this in the verified source.

That makes your operating rule correct: **safety equals allowlist content.** Your allowlist
will contain only the following, and never a raw venue function with a free receiver
argument:

- the Adapter's vault selectors;
- `approve` on the underlying tokens and vault shares, where the spender must be an
  allowlisted target, meaning the Adapter;
- `transfer` on the underlying tokens, where the registry limits recipients to the account
  itself and its owners.

**Verify on-chain:** `whitelist(target, selector)` and `whitelistedTargets(target)` on the
registry, `allowedVaults(vault)` on the Adapter, and the full history in the
`TargetSelectorAdded`/`TargetSelectorRemoved` and `VaultSet` events.

### Point 6: Approvals are uncapped and survive pausing and removal

All three facts are correct: the module does not read `approve` amounts, a removal does not
clear an existing allowance, and pausing the registry also blocks `removeFromWhitelist`. In
practice, on your setup:

- **How allowances are used.** On the IPOR paths, every batch approves only the Adapter, for
  the exact amount of that operation, and the Adapter pulls exactly that amount in the same
  batch. Between operations, the allowance from your account to the Adapter is zero.
- **What this does and does not guarantee.** This is how our backend builds batches; the
  module does not enforce it. You can check it at any time by reading
  `allowance(yourAccount, adapter)` after each operation.
- **The spender itself is safe.** The only spender is your Adapter, which can only send funds
  back to your account, and whose code can only change through the 2-of-2 Safe.
- **Pausing is not needed to remove.** A removal takes effect immediately without pausing.
  To stop the agent instantly, you can act directly as account owner, independently of the
  registry: revoke the session (point 7), uninstall the module, or call `approve(spender, 0)`.

### Point 7: Agent authority on your account

This is the exact session, enabled in the deployment batch:

| Field | Value |
|---|---|
| Validator | SmartSessions `0x00000000008bDABA73cD9815d79069c247Eb4bDA` |
| Signers | 2-of-2: Zyfai backend session key + Zyfai EigenCloud TEE key (addresses disclosed in the deployment batch) |
| Allowed actions | **One:** target = your GuardedExec module, selector = `executeGuardedBatch` (`0x2fc52d90`) |
| Action and UserOp policy | SudoPolicy `0x0000003111cD8e92337C100F22B7A9dbf8DEE301` |
| ERC-1271 / ERC-7739 | **None.** The session cannot sign messages, so the permit / `transferWithAuthorization` path you described does not exist. |
| Paymaster | Allowed, for sponsored gas |
| Expiry | None. You can revoke it at any time with your owner key (`removeSession` on SmartSessions, or by uninstalling the validator). |

We use SudoPolicy on purpose. The session only says that the agent may call this one function.
The restriction is applied by your module and your registry, on every inner call of every
batch.

On the empty-reply behaviour of `callPolicy` that you flagged: we use no call policies, only
SudoPolicy, so that code path is never reached.

The standard SmartSessions on the test account held no permission because that account's
authority went through the Emissary and the IntentExecutor. Your account works the other way
round, as described above.

**Verify on-chain:** the session is readable on SmartSessions for your account from the
deployment block onward: its permission, actions and policies.

### Point 8: Makina

- **Why it appeared.** Makina is one of our integrations. The beacon change you observed was
  the Adapter release that supports it, and admitting the DirectDepositor and AsyncRedeemer
  was integration testing on our test instance. It should not have happened on an instance
  under your review. That is a fair criticism.
- **Your deployment.** It runs the current audited Adapter release, which includes the code
  for Makina and Morpho markets (including borrowing). Having the code is not the same as
  having permission: **no Makina contract and no Morpho market is admitted**. Those functions
  revert on anything that is not allowlisted, and borrowing is inert without an allowed
  market.
- **Makina exit terms.** We agree with your reading of the 3-day finalization delay, the
  single finalizing key and the absence of a timelock on the delay. Admitting it, or any other
  venue, is your decision. Since it requires both signatures on the Safe, it cannot happen
  without you.

**Verify on-chain:** `allowedVaults()` and `allowedMarkets()` on the Adapter, and the absence
of `VaultSet` / `MorphoMarketSet` events for anything other than your IPOR vaults.

---

## 4. What we need from you

1. **The IPOR vaults to allowlist**: their addresses on Base, plus for each one:
   - **Deposits:** are they permissioned? The Adapter is the contract that calls `deposit()`,
     so if the vault restricts depositors, its role must be granted to the Adapter address we
     will send you.
   - **Shares:** are they transferable (public vault) or locked (private vault)? Exits pull
     the shares through the Adapter.
   - **Withdrawals:** are they instant, or do they go through a WithdrawManager (request,
     then claim)? Request-based vaults need one extra Adapter selector. If so, we will list it
     explicitly before deployment.
2. **Your signer address** for the 2-of-2 Safe.
3. **The owner address of your smart account**, which is also the address you will sign in
   with. Tell us whether it is an EOA or a Safe. This is the address we enable for your
   dedicated setup on our side.

## 5. Verification checklist before funding

- Safe: `getOwners()` = [Zyfai signer, your signer] and `getThreshold()` = 2.
- Registry, module, Adapter and beacon: `owner()` = Safe, and `pendingOwner()` = `0x0` on the
  three 2-step contracts.
- Beacon `implementation()` = the reviewed Adapter release. Module `registry()` = your
  registry.
- Registry allowlist and Adapter `allowedVaults` = exactly the agreed IPOR vaults (point 5).
  No Makina, no Morpho market.
- Account: executors = [your module]; validators = [OwnableValidator, SmartSessions]; one
  session, as specified in point 7. No Emissary, no IntentExecutor.
