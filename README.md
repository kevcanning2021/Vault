# BTC Vault

Personal ERC-4626 vault on **Base Sepolia**. Deposit USDC, the vault supplies it to **Aave v3**, and your balance grows in USDC as borrowers pay interest. Only the owner wallet can deposit or withdraw. No fees, no upgradeability.

## How it works

```
You ──USDC──▶ BtcVault ──supply──▶ Aave v3 Pool
   ◀─btcVault shares─┘     ◀──aUSDC (grows every block)──┘
```

- `totalAssets()` = aUSDC held + any idle USDC. Share price rises as aUSDC grows.
- `earned()` = totalAssets − net deposited.
- Minimum deposit: **1 USDC** (`MIN_DEPOSIT`).
- The page shows **per-day earnings**: your balance × today's Aave rate over 24h.
- `maxWithdraw()` is capped by the USDC Aave actually has free right now.
- `emergencyExit()` pulls everything out of Aave and pauses deposits; `resume()` undoes it.
- `rescue()` recovers stray tokens but can never touch USDC or aUSDC.

## Addresses (Base Sepolia, chain 84532)

Source: [bgd-labs/aave-address-book](https://github.com/bgd-labs/aave-address-book/blob/main/src/AaveV3BaseSepolia.sol)

| | Address |
|---|---|
| Aave v3 Pool | `0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27` |
| USDC (Aave test token) | `0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f` |
| aUSDC | `0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC` |

Use Aave's test USDC from the [Aave faucet](https://app.aave.com/faucet/), not Circle's testnet USDC. They are different tokens.

## Quick start (no tools needed)

1. Get test ETH (Base Sepolia faucet) and test USDC (Aave faucet).
2. Open `web/index.html` in a browser with MetaMask/Coinbase Wallet, connect.
3. **Vault setup → Deploy a new vault.** The address is saved in that browser.
4. Deposit. Watch "Earned" tick up.

> The page needs a wallet injected into the browser. It won't find one inside the Claude app on a phone. On mobile, host the page (e.g. GitHub Pages) and open it in your wallet app's built-in browser. On desktop, serve it locally: `npx serve web` then open the URL (wallets don't inject into `file://`).

## Developer route (Foundry)

```bash
git init && forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 foundry-rs/forge-std
forge test               # 15 unit/fuzz tests against mock Aave
BASE_SEPOLIA_RPC=https://sepolia.base.org forge test --match-contract Fork   # real Aave fork test

# Deploy (uses an encrypted keystore — never paste a private key in a command)
cast wallet import dev --interactive
forge script script/Deploy.s.sol --rpc-url https://sepolia.base.org --account dev --broadcast

# After any contract change, refresh the bytecode in the page:
forge build && python3 web/build.py
```

## Layout

```
src/BtcVault.sol              the vault
src/interfaces/IAavePool.sol  minimal Aave Pool interface
test/BtcVault.t.sol           unit, fuzz, and fork tests
test/mocks/MockAave.sol       mock USDC / Pool / aToken
script/Deploy.s.sol           Base Sepolia deploy
web/index.template.html       dApp source (bytecode placeholder)
web/build.py                  injects bytecode → web/index.html
```

## Status

Testnet prototype. **Not audited.** Don't put real funds in it without a professional review — see `IMPROVEMENTS.md`.
