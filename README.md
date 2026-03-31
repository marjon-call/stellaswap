# StellaSwap Security Review

StellaSwap is the leading DEX on Moonbeam (Polkadot), powered by a Vote-Escrow (VE) 3,3 model and a modular V4 AMM built on Algebra's Integral engine.

## In-Scope Contracts

| Contract | Address | Type |
|---|---|---|
| veNFT | `0xfa62B5962a7923A2910F945268AA65C943D131e9` | Direct |
| Algebra Vault Factory | `0x9B81835b2f7B51447D5E4C07Ae18f05dfe627150` | Direct |
| stGLMR Funds Manager | `0x3069A7955408D261069F7D4ed3eFdB9Ea8D95d7b` | Proxy |
| Voter | `0x091a177FbC5f493920c2e027eDc89658c1cED495` | Proxy |

## Build

```bash
forge build
```

Note: OpenZeppelin submodules must be pinned to v4.8.0. If builds fail after `git submodule update`, run:
```bash
cd lib/openzeppelin-contracts && git checkout v4.8.0 && cd ../..
cd lib/openzeppelin-contracts-upgradeable && git checkout v4.8.0 && cd ../..
```

## PoC Tests

```bash
MOONBEAM_RPC_URL="https://rpc.api.moonbeam.network" forge test --match-contract PoCTest -vvv
```

See `poc.md` for detailed PoC writing instructions.

## Project Structure

```
src/
  algebra/       - Algebra Community Vault & Factory (Integral V4 fee handling)
  stglmr/        - stGLMR liquid staking (FundsManager, Ledger)
  venft/          - veSTELLA NFT (vote-escrow locking)
  voter/          - Voting contract, IncentiveManager, rewards
  interfaces/    - Shared interfaces
  libraries/     - Shared libraries
```
