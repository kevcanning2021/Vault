# Lessons Learnt — BTC Vault (2026-10-13)

## Product / scoping
- **"Without transferring assets" isn't literally possible for a vault.** USDC always moves into a contract. What users really want is *non-custodial*: only they can withdraw. Say this up front.
- **For a single user, a vault adds risk.** Supplying straight to Aave gives aUSDC in your own wallet with zero custom code. A vault only pays off once you add automation, multiple users, or strategy switching.
- **"BTC" was branding only.** Asking that early stopped me building BTC collateral logic nobody needed.

## Aave on testnets
- **Aave testnets use their own test tokens.** Base Sepolia USDC for Aave is `0xba50…4D5f`, not Circle's USDC. Using Circle's token makes `supply()` revert.
- **The authoritative address source is `bgd-labs/aave-address-book`.** Blog posts and SDK examples carried a wrong/other-network pool address.
- **Withdrawals depend on Aave liquidity.** If borrowers have taken the cash, you can't pull it all out. `maxWithdraw` must reflect that, or the UI's "Max" button will fail.

## ERC-4626
- **The fuzz test caught virtual-share leakage.** OpenZeppelin's inflation defence (1 virtual asset) takes a cut of yield proportional to `1 / totalAssets`. With a 1-wei deposit and big interest it took ~50%. At ≥ 1 USDC it's under 1 part per million. Tests now use a realistic minimum and assert the exact bound.
- **Owner-only deposits remove the inflation attack** entirely, but the offset is kept as a belt-and-braces default.
- Track `netDeposited` on-chain so "Earned" doesn't depend on the browser remembering anything.

## Tooling in this sandbox
- `foundryup` and `binaries.soliditylang.org` are blocked; GitHub release downloads work. Install forge and `solc-static-linux` from GitHub and pass `--use <solc>`.
- Public RPCs are blocked here, so the fork test can only run on Kevin's machine.
- `anvil` + ethers reading the ABI/bytecode straight out of the built page is a fast way to prove the page and contract agree.

## Frontend
- Artifact pages run in a sandboxed frame. A browser wallet may not inject there, and never inside the mobile app. Ship the page as a file too and document how to host it.
- Embedding the bytecode lets the user deploy from the page with one tap, no Foundry needed. Keep `build.py` as the single way to refresh it so the page never drifts from the contract.
