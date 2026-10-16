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

## Iteration 2 (minimum deposit + daily earnings)
- **Enforce the minimum in the contract, not just the page.** `mint()` routes through `_deposit` too, so one check in `_deposit` covers both entry points.
- **"Daily earnings" is a projection.** Aave's rate moves every block, so the page labels it "at today's rate". True historical daily earnings need snapshots (see IMPROVEMENTS #6).

## Iteration 3 (hosting for SafePal mobile)
- Ask which wallet early: mobile wallets need a hosted HTTPS page opened in their DApp browser.
- This session can push to an existing repo but can't create repos or change Pages settings; Kevin creates the repo and flips Pages on (Settings → Pages → main /docs).

## Iteration 4 (getting test ETH)
- **Test ETH was the hardest step, not the code.** Alchemy/QuickNode faucets need 0.001 real ETH on mainnet; Coinbase's CDP faucet returned "page not found" on mobile; it worked on desktop.
- Lead with the desktop Coinbase CDP faucet (login only, no mainnet balance) and mention the mainnet-balance gate up front.
- Claude in Chrome showed as "not connected" from this cloud session even with the extension working locally. Don't burn turns retrying; offer the manual 4-click route early.

## Iteration 5 (mainnet prep)
- **Ask the money questions before building mainnet** (amount, cap, owner, page layout). The answers changed the design: a cap became a constructor arg plus setter.
- **OZ ERC4626 already enforces `maxDeposit`**, so capping there covers `deposit`; `maxMint` must convert the same room to shares. Keep a second check in `_deposit` as a backstop.
- **Lowering the cap must never block withdrawals.** Tested explicitly.
- **`vm.prank` only covers the next call.** `vault.redeem(vault.balanceOf(me), ...)` pranks `balanceOf`, not `redeem`. Read values into locals first.
- **Keep the page backward compatible.** Old vaults have no `depositCap()`; the page catches the revert and shows "none (older vault)".
- **Store vault addresses per chain** (`vault:<chainId>:<wallet>`) so test and real vaults never get mixed up.

## Iteration 6 (second lender: Compound v3)
- **Check testnet availability before choosing a protocol.** Compound has no Base Sepolia deployment, and Aave/Circle testnets use different USDC tokens, so a two-lender vault can't be tried end-to-end on testnet. The mainnet fork test becomes a hard gate.
- **Validate the integration at deploy time**: the constructor checks `comet.baseToken() == usdc`, so a wrong Comet address fails loudly instead of losing funds later.
- **Withdraw from both lenders.** After a move, interest or dust can remain on the old lender; `_withdraw` tries the current one first, then the other.
- **Use Compound's "withdraw all" (`type(uint256).max`)** when emptying a position to avoid 1-wei leftovers.
- **ERC-4626 rounding leaves ≤1 wei of dust** after a full redeem. Tests assert `≤ 1`, not `== 0`.
- Kevin said "go with your recommendation" when no single pick had been stated. Name the pick and the reason in the first line before building.

## Iteration 7 (first live review)
- **Read on-chain state via Blockscout's API** (`base-sepolia.blockscout.com/api/v2/addresses/<addr>/...`) through WebFetch when RPC and BaseScan are blocked here.
- **Testnet yield is near zero** (~0.03% APY on Base Sepolia Aave): too few borrowers. Don't promise visible testnet earnings; check the APY first.
- **Mobile wallets under-estimate gas** for lending calls. Estimate in the page and add a buffer; a failed tx on mainnet still costs gas.
- **Wait for the allowance to land before depositing.** Two testnet deposits reverted right after an approve.
- "Are you crazy?" came from depositing 10,000 test USDC sounding like real money. Always say "test" / "$0" next to testnet amounts.

## Iteration 8 (fork test on Kevin's Windows PC)
- Cowork's device shell can't mount folders until a Windows update is installed; deliver a PowerShell script via device_commit_files and read its log back with device_stage_files instead.
- Public Base RPCs rate-limit forks (Cloudflare 525 pages). Rotate several RPCs and throttle with `--fork-retries/--fork-retry-backoff/--compute-units-per-second`.
- **Those flags require `--fork-url`.** My first script omitted it and every run failed at argument parsing. Check a CLI's argument parsing locally before shipping a script.
- Write results to a log file the user doesn't have to screenshot.
- Unit tests: 29/29 passed on Kevin's machine (2026-10-16).
