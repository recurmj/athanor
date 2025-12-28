# Athanor Contracts (Foundry)

Minimal on-chain stack for Athanor (permissioned pull demo):

1) **AthanorConsentRegistry** — on-chain nonce revocation (the QUENCH button)
2) **AthanorPullExecutor** — EIP-712 Authorization validation + capped pull execution
3) **AthanorStrategyAllowlist** — safe-ish strategy adapter that can call allowlisted targets

> ⚠️ Experimental / not audited. Use small test capital.

## Install

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge install foundry-rs/forge-std --no-commit
```

## Configure

```bash
cp .env.example .env
# edit .env
source .env
```

## Deploy to Base mainnet

```bash
forge script script/DeployBase.s.sol:DeployBase --rpc-url $RPC_URL --broadcast
```

After deploy, set your app env vars:

- `NEXT_PUBLIC_REGISTRY=<REGISTRY>`
- `NEXT_PUBLIC_EXECUTOR=<EXECUTOR>`
- `NEXT_PUBLIC_STRATEGY=<STRATEGY>`

## Notes
- Strategy calls are allowlisted (you can add UniswapX/other targets as needed).
- Keep caps small for first tests (LOW FIRE).


## Two modes
- **Proof Mode**: strategyData empty => NO-OP strategy => pure return.
- **Live Mode**: strategyData encodes allowlisted external call.
