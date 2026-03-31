# StellaSwap Documentation Summary

> Summarized from 63 pages crawled from https://docs.stellaswap.com/ on 2026-03-31.

## Protocol Overview

StellaSwap is the leading DEX on Moonbeam (Polkadot parachain). It is an EVM-based hybrid-AMM DEX powered by a Vote-Escrow (VE) 3,3 model and a modular V4 AMM built on Algebra's Integral engine. The protocol offers swaps, concentrated liquidity provisioning, liquid staking (stGLMR/stDOT), and vote-escrow governance.

## Core Components

### 1. StellaSwap V4 AMM (Algebra Integral)

- **Engine:** Concentrated liquidity core developed by Algebra (licensed exclusively for Moonbeam).
- **Plugins:** Modular plugin architecture (similar to UniV4 hooks but upgradeable without liquidity migration). Enables dynamic fees, limit orders, gas optimizations, JIT liquidity solutions, and IL reduction.
- **Gas:** Outperforms UniV4 in single swaps and large trades; slightly less efficient in multihop swaps.
- **Capital Efficiency:** Up to 4,000x vs standard AMMs. Liquidity utilization target >50%.
- **Flashloans:** Pulsar V3 pools expose a `flash` method for flash loans via `IAlgebraFlashCallback`.

### 2. Vote-Escrow STELLA (veSTELLA) — VE(3,3)

Based on Andre Cronje's VE(3,3) model combining Curve's locking mechanism with OlympusDAO's game theory. Inspired by Solidly, Velodrome, and Aerodrome.

**Mechanics:**
- Users lock STELLA tokens to receive veSTELLA, an ERC-721 NFT.
- Voting power is proportional to amount locked and lock duration (max 2 years).
- **Linear decay:** Voting power decreases daily over the lock period.
- **Epoch:** 1 week, ending Thursdays at 23:59 UTC.
- **Cool-down period:** 1 hour at start and end of each epoch where voting is blocked.
- Voters earn swap fees directly from pools they vote for (Solidly-style direct-pool-earning, not Curve-style global distribution).

**NFT Operations:**
- **Create Lock:** Lock STELLA for 1 week to 2 years. Rounded down to weeks.
- **Increase Amount:** Add more STELLA to an existing lock.
- **Extend Duration:** Extend lock end time (cannot shorten).
- **Merge:** Combine two locks into one; inherits the longer duration.
- **Split:** Split a lock into two; both inherit the same duration.
- **Transfer:** Transfer lock ownership to another address.
- **Early Withdraw:** Break a lock before expiry with a **50% penalty** (burned to dead address).
- **Emergency Withdraw:** Available only when toggled on by admin.

**Managed NFTs:**
- Users can deposit their veNFT into a "Managed NFT" (auto-strategy).
- Managed NFTs aggregate voting power from deposited locks.
- Two built-in strategies: STELLA Optimizer (compounds to max lock) and USDC Optimizer (converts earnings to stables).
- 1% fee on auto-strategy earnings; 1-epoch delay for claims.

### 3. Voting & Emissions

- veSTELLA holders control **100% of STELLA emissions** by voting each epoch.
- Emissions start at 40,000 STELLA/day, decreasing 0.25% per epoch (deflationary).
- Votes direct emissions to liquidity pools. More votes = more emissions to that pool.
- Max 30 votes per NFT per epoch.
- Voting can be split across multiple pools with custom weights.
- Votes are final per epoch and cannot be reversed.

**Reward Distribution:**
- Trade fees from voted pools go to voters pro-rata.
- STELLA emission rewards distributed to pools based on vote share.
- Off-chain rewarder calculates rewards every 5 minutes, distributes every 1 hour.
- LPs earn automatically upon position creation (no separate staking step needed).

### 4. Bribes

- Protocols or any user can attach bribes to pools to attract veSTELLA voter attention.
- Bribes are distributed to voters who voted for the bribed pool.
- Whitelisted bribe tokens only (admin-controlled whitelist, currently 24 tokens).
- Creates a flywheel: protocols bribe -> voters vote -> pool gets emissions -> deeper liquidity -> more fees -> more attractive to bribe.

### 5. Liquid Staking

#### stGLMR (In-Scope)
- Liquid staking derivative for GLMR (Moonbeam's native token).
- **Yield-bearing** (not rebasing): stGLMR value increases as rewards accrue, balance stays the same.
- Exchange rate: `shares = GLMR * totalShares / totalPooledGLMR`.
- Protocol delegates GLMR across multiple collator ledgers on Moonbeam.
- **10% fee** on staking rewards (sent to treasury as minted stGLMR shares).
- **Unbonding period:** ~7 days on Moonbeam (28 rounds).
- Users can redeem stGLMR -> GLMR via unstaking (delayed) or instant swap on Pulsar pools.
- **Architecture:** FundsManager orchestrates deposits/redemptions across multiple Ledger proxies. Each Ledger delegates to a specific collator candidate. Rebalancing happens once per staking round.

#### stDOT (Not In-Scope)
- Similar model for Polkadot DOT staking via XCM.
- 28-day unbonding period.
- 3 audits completed (Mixbytes, Peckshield, SolidProof).

### 6. Algebra Community Vault (In-Scope)

- Receives community fees from V4 Algebra pools.
- On withdrawal, fees are split:
  - **Algebra fee** portion -> Algebra fee receiver
  - **Community fee** portion -> Community fee receiver
  - **Remainder** -> Pool's fee distributor (IncentiveManager) via `notifyRewardAmount`, or to community fee receiver if no distributor is set.
- AlgebraVaultFactoryStub creates per-pool vault instances and manages fee parameters.
- Fee denominator: 1000 (fees in thousandths).

## Key Contract Addresses (Moonbeam)

### In-Scope (Bug Bounty)
| Contract | Address | Type |
|---|---|---|
| veNFT | `0xfa62B5962a7923A2910F945268AA65C943D131e9` | Direct |
| Algebra Vault Factory | `0x9B81835b2f7B51447D5E4C07Ae18f05dfe627150` | Direct |
| stGLMR Funds Manager | `0x3069A7955408D261069F7D4ed3eFdB9Ea8D95d7b` | Proxy |
| Voter | `0x091a177FbC5f493920c2e027eDc89658c1cED495` | Proxy (UUPS) |

### Supporting Contracts
| Contract | Address |
|---|---|
| STELLA Token | `0x0E358838ce72d5e61E0018a2ffaC4bEC5F4c88d2` |
| WGLMR | `0xAcc15dC74880C9944775448304B263D191c6077F` |
| stGLMR Token | `0x7d7164cFAc019872a3890b686306a3B8c5c5Ba73` |
| stGLMR AuthManager | `0x1b194c25f1915b4A96781a4eaB7f31e78e38eA03` |
| stGLMR Withdrawal | `0x8ff3c99bFE873F1Aa83d867B999FB7554964D8DD` |
| AlgebraFactory (V4) | `0xabE1655110112D0E45EF91e94f8d757e4ddBA59C` |
| SwapRouter (V3) | `0xe6d0ED3759709b743707DcfeCAe39BC180C981fe` |
| V2 Factory | `0x68A384D826D3678f78BB9FB1533c7E9577dACc0E` |
| V2 Router | `0x70085a09D30D6f8C4ecF6eE10120d1847383BB57` |
| IncentiveManagerFactory | `0xe40d3077e6aE25bA3edB4479535A19F78Ad0a423` |
| Minter | `0x9E5766e37A5b0cC60229f102f37F35f9DCdD8A90` |

### stDOT Contracts (Not In-Scope)
| Contract | Address |
|---|---|
| ProxyAdmin | `0xe8A5C0039226269313c89C093a6c3524c4d39fa4` |
| Controller | `0x002D34d6a1b4A8E665fEc43Fd5D923F4d7Cd254f` |
| AuthManager | `0x5927e31Cd0b8213892fb0C44F7C1c94DCB830263` |
| Oracle | `0x0Fa8cdE3e0cDDF150d79add0f3d63CB6E0F2F079` |
| OracleMaster | `0x3B23F0675fFc45153ECA239664CCaEFc5E816B9C` |
| Withdrawal | `0xa2D7009eA7502cD796d174fFaA7e26eCe8edEAcF` |
| Nimbus | `0xbc7E02c4178a7dF7d3E564323a5c359dc96C4db4` |

## Tokenomics

- **Ticker:** STELLA
- **Max Supply:** 250,000,000 (reduced from 500M via burn)
- **Allocation:** Ecosystem Growth 10%, Treasury 12.5%, Development 12.5% (5-year vest, quarterly unlocks from Jan 2022)
- **Emissions:** Deflationary — 0.25% weekly reduction in STELLA emitted per epoch.

## Security & Audits

| Scope | Auditor | Notes |
|---|---|---|
| V2 AMM | Certik, SolidProof | Full contract audit |
| Stable AMM | SolidProof | Full audit |
| Pulsar V3 (Algebra) | ABDK Consulting, Hexen | Core AMM audit |
| Pulsar V3 | Code4rena | Bounty contest (joint with Quickswap) |
| stDOT | Mixbytes, Peckshield, SolidProof | 3 separate audits |
| stGLMR | AstraSec | 1 audit |
| Ongoing | Immunefi Bug Bounty | Critical: $1K-$2.3K, High: $1K-$1.3K |

**Notable:** No public audits found for the veSTELLA/Voter contracts or the Algebra Vault Factory specifically.

## Cross-Contract Relationships

```
STELLA Token
    |
    v
veNFT (locks STELLA -> veSTELLA NFTs)
    |
    v
Voter (veSTELLA holders vote on pools)
    |--- registers pools -> creates IncentiveManagers (fee + bribe)
    |--- distributes STELLA emissions based on votes
    |--- calls Minter.mintForEpoch() each epoch
    |
    v
AlgebraVaultFactoryStub (manages community fee vaults per pool)
    |--- creates AlgebraCommunityVault per pool
    |--- routes fees to pool's IncentiveManager (fee distributor)
    |--- references Voter for fee distributor lookup
    |
    v
FundsManager (stGLMR protocol core)
    |--- manages GLMR deposits/redemptions
    |--- orchestrates Ledger proxies (delegate to collators)
    |--- mints stGLMR shares for treasury fees
    |--- interacts with Withdrawal contract for user claims
```

## Key Protocol Parameters (Live State at Block 15034800)

| Parameter | Value |
|---|---|
| veNFT total supply (voting power) | ~52.16M veSTELLA |
| veNFT STELLA locked | ~55.6M STELLA |
| veNFT token count | 1,364 minted |
| Voter epoch duration | 1 week |
| Voter pool count | 26 |
| Voter cool-down | 1 hour |
| Voter max votes/epoch | 30 |
| Voter reward tokens | 1 (STELLA) |
| Voter bribe whitelist | 24 tokens |
| stGLMR AUM | ~1.094M GLMR |
| stGLMR deposit cap | 10M GLMR |
| stGLMR treasury fee | 10% (1000 bps / 10000) |
| stGLMR ledger count | 8 |
| stGLMR unbond delay | 28 rounds |
| Algebra fee | 15/1000 (1.5%) |
| Community fee | 150/1000 (15%) |
