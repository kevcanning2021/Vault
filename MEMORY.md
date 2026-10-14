# Project Memory — BTC Vault

Quick context for whoever picks this up next (human or Claude).

## Decisions (made by Kevin, 2026-10-13)
| Topic | Decision |
|---|---|
| Scope | Smart contract + web app |
| Yield source | Aave v3, plus Compound v3 as second lender (added 2026-10-14); owner moves funds between them manually |
| Chain | Base (Base Sepolia testnet first) |
| "BTC" | Brand name only — pure USDC in, USDC out |
| Users | Just Kevin (owner-only deposits) |
| Fees | None |
| Frontend | Claude's call → single HTML page, ethers v6.13.4 |
| Upgradeability | None (immutable) |
| Minimum deposit | 1 USDC, enforced in contract and page (2026-10-13) |
| Daily earnings | Shown on page as projection: balance × today's Aave rate (2026-10-13) |
| Real money plan | Start under $100; owner = SafePal wallet; owner-adjustable deposit cap starting at 100 USDC; one page with Test/Real network switch (2026-10-13) |

## Current state
- Contract: `src/BtcVault.sol`, compiles with solc 0.8.26, 12.1 KB bytecode.
- Tests: 29 unit/fuzz passing (1,000 fuzz runs). Fork test written, not yet run (needs RPC access).
- End-to-end: page ABI + bytecode verified on a local anvil chain (deploy, deposit, accrue, redeem).
- Page: published as a private artifact "BTC Vault"; same file at `web/index.html`.
- Repo: github.com/kevcanning2021/vault (public). Page served by GitHub Pages from `main` /docs → https://kevcanning2021.github.io/vault/
- Kevin uses the **SafePal mobile app**: open the Pages URL in SafePal's DApp browser.
- **Deployed on Base Sepolia by Kevin (2026-10-13)** from the page. Vault address: `0xC2831B377558Db5093FbE8F5295d8F0E65D1F889` (https://sepolia.basescan.org/address/0xC2831B377558Db5093FbE8F5295d8F0E65D1F889).
- Live test 2026-10-13: deposited 2 USDC, withdrew 1 USDC via SafePal mobile — both worked. Left running to observe yield.

## Key addresses (Base Sepolia, 84532)
- Pool `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27`
- USDC (Aave test) `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f`
- aUSDC `0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC`

## Base mainnet (8453)
- Pool `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5`, USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`, aBasUSDC `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB`
- Compound v3 cUSDCv3 `0xb125E6687d4313864e53df431d5425969c15Eb2F` (source: compound-finance/comet deployments/base/usdc/roots.json)
- Compound has **no Base Sepolia deployment**, so testnet vaults are Aave-only (COMET = 0). Compound path is proven by mocks + Base fork test only.
- See MAINNET_CHECKLIST.md for go-live gates. Not deployed yet.
- The existing testnet vault (0xC283…F889) predates the cap; page shows "none (older vault)" for it.

## Mainnet notes
- Base mainnet uses native USDC and a different Pool. Pull both from `AaveV3Base.sol` in the address book; never copy from a blog.
- Deploy script refuses to run on any chain but 84532 on purpose. Add a separate mainnet script.

## Conventions
- After any contract edit: `forge build && python3 web/build.py`, then republish the page.
- Never put a private key on the command line. Use `cast wallet import` keystores.
