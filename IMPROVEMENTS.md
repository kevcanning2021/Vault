# Possible Improvements — BTC Vault

Ordered roughly by value. ⚠ = do before real money.

## Before mainnet
1. ⚠ **Independent security review.** Even a personal vault holds real funds once on mainnet.
2. ⚠ **Run the fork test** on your machine against Base Sepolia, then against Base mainnet (`AaveV3Base` addresses).
3. ⚠ **Mainnet deploy script** with Base mainnet Pool / native USDC / aUSDC from the address book, plus a chain-id guard.
4. ⚠ **Hardware wallet or Safe as owner.** Owner = the only key that can move funds. Consider a 2-of-3 Safe.
5. **Respect Aave supply caps and pauses in `maxDeposit`** so the page shows a clear message instead of a revert when USDC supply is capped or frozen.

## Product
6. **Yield history chart** — record `totalAssets` per day (event log or a small indexer) and draw earned-over-time.
7. **Rate comparison** — show Aave vs Morpho vs Compound USDC rates; later, a strategy switcher (needs careful design and a timelock).
8. **Auto-buy BTC with yield** (if "BTC" ever becomes more than branding): periodically swap earned USDC to cbBTC via a DEX with slippage limits.
9. **Merkl / Aave rewards claiming** — collect any incentive tokens Aave pays and convert them to USDC.
10. **Multi-user mode** — remove the owner gate, add a per-user cap and deposit limit, keep the virtual-share offset.

## Engineering
11. **Invariant tests** (Foundry `invariant_`): totalAssets ≥ sum of redeemable assets; shares never mint without assets.
12. **Gas**: replace `type(uint256).max` approval at construction with exact approvals if the pool address could ever be swapped (it can't today; it's immutable).
13. **CI**: GitHub Action running `forge test` + `python3 web/build.py` diff check, so the page bytecode can't drift from the contract.
14. **Host the page** on GitHub Pages so it opens in MetaMask Mobile's browser.
15. **Next.js + wagmi** version if this grows into a shared product (WalletConnect for mobile without a wallet browser).
