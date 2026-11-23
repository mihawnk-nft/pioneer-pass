# AgentBadge — Agent Pioneer Badge

> **Working name.** Final project name to be confirmed by the user before deploy.
> Do NOT use "Binance" / "BNB" in the final project name, token name, or domain
> (hackathon red line). The repo name `binance-agent-badge` is a working
> identifier only — rename it to the final name before submit if needed.

Free ERC-721 badge + daily check-in streak for **Agent ID** holders, built for the
**Binance Agent ID Hackathon 2026** (submit 18 Nov → 9 Dec 2026 15:00 WIB).

## Concept (Ide 5 — Hybrid)

1. **Mint a free badge** — 1 per Agent ID holder (gas only, badge is free).
2. **Check in daily** — 1x/day builds an on-chain streak; the badge levels up
   (Bronze → Silver → Gold). The badge becomes an agent's "activity passport".

This attacks both Pioneer metrics at once: unique Agent ID addresses (free mint)
**and** transaction count (daily check-ins). The Agent ID gate lives **in the
contract** (not just the frontend) — the strongest integration pattern.

## Contract — `src/AgentBadge.sol`

- **ERC-721** "Agent Pioneer Badge" (`APB`), dependency-free minimal
  implementation written from scratch (no OpenZeppelin — see note below).
- **Gate (on-chain):** `mint()` and `checkIn()` both require
  `balanceOf(caller) > 0` on the SPACE ID Agent ID contract
  `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`
  (verified via `eth_getCode` on BSC mainnet, 23 Nov 2026 — contract has code).
- **1 mint per address** — second mint reverts (`AlreadyMinted`).
- **Daily check-in:** 1x/day per address. Consecutive days grow the streak;
  a missed day resets it to 1. Second check-in the same day reverts.
- **Levels:** `levelOf()` — 0 none, 1 Bronze (streak 1–6), 2 Silver (7–29),
  3 Gold (30+).
- **Events:** `BadgeMinted`, `CheckedIn` (for distribution monitoring).
- **Owner:** deployer only, for `setBaseURI()` (badge metadata).

### Red lines honoured

- This contract **never touches the user's Agent ID NFT** (no transfer/sale of it).
- No seed/key collection. No bypass of user confirmation. No promised returns.
- No "Binance"/"BNB" in the token name or symbol.
- No volume manipulation, no mass accounts — interactions must come from real
  Agent ID holders.

## Build & test (Foundry 1.9.0)

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test        # 12 tests, all passing
forge test --gas-report
```

Tests (`test/AgentBadge.t.sol`, no forge-std — cheatcode interface is defined
locally in the test file, mock Agent ID included):

| Test | What it proves |
|---|---|
| `testMint_RevertsForNonHolder` | mint gate: non-holder reverts |
| `testMint_Success` | holder mints, gets token 1 |
| `testMint_SecondMintReverts` | 1 mint per address |
| `testCheckIn_RevertsWithoutBadge` | check-in needs a badge |
| `testCheckIn_Success` | streak 1, totalCheckIns 1 |
| `testCheckIn_TwiceSameDayReverts` | 1 check-in per day |
| `testCheckIn_StreakIncrements` | 3 consecutive days → streak 3 |
| `testCheckIn_StreakResetsAfterGap` | missed days reset streak to 1 |
| `testCheckIn_RevertsIfAgentIdLost` | losing Agent ID blocks check-in |
| `testLevel_BronzeSilverGold` | levels 0 → 1 → 2 (streak 7) → 3 (streak 30) |
| `testTransfer_BasicERC721` | transfer updates owner/balances |
| `testTokenURI` | baseURI + token id |

## Gas (measured 23 Nov 2026, BSC mainnet RPC)

| Action | Gas |
|---|---|
| Deploy (contract creation) | **2,535,038** (estimated via `eth_estimateGas`, BSC dataseed) |
| Mint (first, cold storage) | ~125,673 |
| Check-in (first) | ~99,063 |
| Check-in (later) | ~48,045 avg |

Deploy cost at current gas price (0.05 gwei, 23 Nov): ~0.00013 BNB.
At 1 gwei: ~0.00254 BNB. **User wallet balance 23 Nov: ~0.00198 BNB**
(down from 0.00287) — deploy is affordable at current low gas, but NOT at
1 gwei. Recheck balance + gas price before deploy; top up BNB or deploy
during low gas.

## Why no OpenZeppelin / forge-std?

This repo is intentionally **dependency-free**: the ERC-721 is written from
scratch and the test cheatcode interface is defined locally. Reason: the
standard `forge-std` library clone was flagged by an execution-risk check
during setup, so no third-party code is vendored or committed here
(`lib/` is gitignored). The contract is small (runtime 10,999 bytes, well
under the 24,576 limit) and fully covered by tests. Before mainnet deploy,
the team may switch to audited OpenZeppelin ERC-721 — that is a deliberate
decision for the deploy step, not a silent change.

## Status

- [x] Tahap 1 — contract design (this repo)
- [x] Tahap 2 — local tests (12/12 passing)
- [ ] Tahap 3 — deploy to BSC mainnet + verify on BscScan (needs: DevMode
      reactivated, BNB balance rechecked, deploy method + prize-address decision)
- [ ] Tahap 4 — frontend (1 page, GitHub Pages)
- [ ] Tahap 5 — end-to-end test with user wallet
- [ ] Tahap 6 — launch + distribution (target: 30+ real Agent ID holders)
- [ ] Tahap 7 — submit (preview + explicit user YES first)

## License

MIT — see `LICENSE`.
