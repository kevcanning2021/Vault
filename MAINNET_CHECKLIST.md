# Going to Real Money — Checklist

Plan agreed 2026-10-13: start **under $100**, owner = Kevin's SafePal wallet, vault starts with a **100 USDC cap**.

Tick each box in order. Don't skip ahead.

## 1. Testnet proof ✅ done
- [x] Deploy on Base Sepolia
- [x] Deposit and withdraw work from SafePal mobile
- [x] Earned is above 0 after 24–48 hours (0.000215 on 100 USDC; testnet rate ~0.03%, so tiny but real)
- [x] Emergency exit → withdraw → resume all work on testnet (Kevin, 2026-10-16)
- [x] Deploy a **fresh testnet vault** from the new page (has the deposit cap) and try going over the cap — it should refuse (Kevin, 2026-10-16)

## 2. Code checks
- [x] 29 unit/fuzz tests pass, including cap and Aave ↔ Compound move tests (also on Kevin's PC, 2026-10-16)
- [x] Page ↔ contract verified on a local chain (cap, deposit, over-cap rejection, redeem)
- [ ] **Hard gate (Compound can't be tested on testnet):** Base mainnet fork test passes on Kevin's machine:
  Windows: `powershell -ExecutionPolicy Bypass -File "$HOME\Documents\run-fork-test.ps1"` (copy in tools/)
- [ ] Optional but recommended for anything above ~$1,000: independent security review

## 3. Wallet prep (real money)
- [ ] SafePal on **Base** network (not Ethereum mainnet)
- [ ] ~$1 of ETH on Base for gas (deploy + approve + deposit is a few cents)
- [ ] USDC **on Base**. It must be native USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
  (not USDbC). Buying inside SafePal or withdrawing from an exchange to the **Base** network both work.

## 4. Go live
1. Open the vault page in SafePal → tap **Real money · Base**
2. Vault setup → **Deploy a new vault** → confirm (cap starts at 100 USDC)
3. Deposit **10 USDC** first. Check it on basescan.org
4. Withdraw **5 USDC**. Confirm it lands in SafePal
5. Tap **Move to Compound**, check the balance is unchanged, withdraw 1 USDC, then move back if you prefer
6. Then deposit the rest (up to the cap)
7. Raise the cap later under Vault setup only once you're comfortable

## Addresses (Base mainnet, chain 8453)
Source: bgd-labs/aave-address-book `AaveV3Base.sol`, checked 2026-10-13
| | Address |
|---|---|
| Aave v3 Pool | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| USDC (native) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| aBasUSDC | `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB` |
| Compound v3 cUSDCv3 | `0xb125E6687d4313864e53df431d5425969c15Eb2F` |

## Risks you're accepting
- **Unaudited contract.** A bug could lock or lose funds. The cap limits how much is exposed.
- **Compound risk.** Same kind of risk as Aave; you only carry it while funds sit on Compound.
- **Aave risk.** If Aave has a problem, funds can be delayed or lost. Aave is the most battle-tested lending market, but it's not risk-free.
- **Phone wallet = one key.** If your SafePal seed phrase leaks, the vault can be emptied. Never share it.
- **USDC depeg risk.** USDC is a stablecoin issued by Circle; it is designed to stay at $1 but that isn't guaranteed.
