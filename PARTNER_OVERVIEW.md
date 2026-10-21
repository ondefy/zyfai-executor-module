# Your Dedicated ZyFAI Execution Infrastructure

## What we built for you

ZyFAI normally runs its yield automation through a set of shared on-chain
contracts. For you, we deployed a **dedicated, independent copy of that
infrastructure** — your own instance, separate from everyone else's, on Base:

| Component | What it does | Address |
|---|---|---|
| **Target Registry** | Your allowlist. It defines exactly which protocols, vaults and actions the automation is allowed to touch. Nothing outside this list can ever be executed. | `0xE23791a655Ad7707DB955d3a86f5e4e647799D95` |
| **Executor Module** | The gatekeeper installed on your smart account. Every action the automation takes goes through it, and it refuses anything your registry has not approved. | `0x9d7d5F76d8f529e4dDcDF7aC62e11A36e516BE17` |
| **Adapter** | The single entry point used to deposit into and withdraw from vaults. It is built so that funds can only ever return to your own smart account — there is no way to redirect them anywhere else. | `0x4439eF06551D0580B4ebc5c2a2AB87cF4C1F9c64` |
| **Adapter beacon** | The upgrade key of the Adapter: whoever owns it decides which code the Adapter runs. It transfers to you together with everything else. | `0x0b7367de36Bc208E0A223fE5dCDcb89645c4E002` |

All four contracts are deployed, verified on BaseScan, and already tested
end-to-end with a real deposit and withdrawal on a live vault.

## How the security model works

The ZyFAI agent optimizes yield for accounts using this stack, but it operates
inside hard, on-chain boundaries that **you** define:

- The agent can only call the contracts and functions listed in **your**
  Target Registry. Add a vault → the agent can use it. Remove it → the agent
  cannot, immediately, no exceptions.
- Deposits and withdrawals are forced through **your** Adapter, which
  hardcodes your smart account as the only possible recipient of funds. Even a
  fully compromised agent key could not send your funds to a third party.
- None of these contracts ever hold funds. Assets sit in your smart account or
  in the vaults you approved.

In short: we run the engine, you own the rails it runs on.

## Ownership

Today the four contracts are owned by a ZyFAI deployer account (needed for the
initial setup and testing). The next step is a **full ownership transfer to
you**, using a two-step handover wherever the contracts support it: we propose
the transfer, and it only takes effect once you accept it from your own wallet —
so ownership can never land at a wrong address. (The beacon transfers in a
single step; we verify the destination address with you before sending it.)

**Once the transfer is complete, ZyFAI has zero control over this
infrastructure.** We cannot modify your allowlist, cannot change or upgrade the
contracts, cannot add or remove vaults. Only you can. Managing the allowlist
(adding a new protocol, removing one, adjusting approved tokens) is done by
signing straightforward transactions with your owner wallet — we provide the
tooling and documentation, and we're happy to advise, but the keys are yours.

## What ZyFAI keeps doing

- Running the yield automation (allocation, rebalancing, monitoring) — always
  within the limits of your registry.
- Maintaining the off-chain services, dashboards and alerts.
- Supporting you when you want to expand your allowlist to new protocols.

## Summary

- Dedicated registry + executor + adapter, deployed and battle-tested for you
  on Base.
- Funds can only move between your smart account and vaults you approved, and
  can only ever be withdrawn back to your own account.
- Ownership transfer to you is scheduled; after it completes, this
  infrastructure is fully and exclusively yours — permanently.
