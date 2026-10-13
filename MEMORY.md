# Project Memory — BTC Vault

Quick context for whoever picks this up next (human or Claude).

## Decisions (made by Kevin, 2026-10-13)
| Topic | Decision |
|---|---|
| Scope | Smart contract + web app |
| Yield source | Aave v3 |
| Chain | Base (Base Sepolia testnet first) |
| "BTC" | Brand name only — pure USDC in, USDC out |
| Users | Just Kevin (owner-only deposits) |
| Fees | None |
| Frontend | Claude's call → single HTML page, ethers v6.13.4 |
| Upgradeability | None (immutable) |

## Current state
- Contract: `src/BtcVault.sol`, compiles with solc 0.8.26, 9.5 KB bytecode.
- Tests: 12 unit/fuzz passing (1,000 fuzz runs). Fork test written, not yet run (needs RPC access).
- End-to-end: page ABI + bytecode verified on a local anvil chain (deploy, deposit, accrue, redeem).
- Page: published as a private artifact "BTC Vault"; same file at `web/index.html`.
- **Not deployed yet.** Kevin deploys from the page or with `forge script`.

## Key addresses (Base Sepolia, 84532)
- Pool `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27`
- USDC (Aave test) `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f`
- aUSDC `0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC`

## Mainnet notes (for later)
- Base mainnet uses native USDC and a different Pool. Pull both from `AaveV3Base.sol` in the address book; never copy from a blog.
- Deploy script refuses to run on any chain but 84532 on purpose. Add a separate mainnet script.

## Conventions
- After any contract edit: `forge build && python3 web/build.py`, then republish the page.
- Never put a private key on the command line. Use `cast wallet import` keystores.
