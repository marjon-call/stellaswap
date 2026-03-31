# Proof of Concept Guide

## PoC Template

Use `test/PoC.t.sol` as your starting point. It contains:
- Minimal interfaces for all 4 in-scope contracts (IVeNFT, IAlgebraVaultFactory, IFundsManager, IVoter, IERC20)
- All contract addresses (proxy and direct) with typed references
- A Moonbeam mainnet fork at block 15034800

## Running Tests

```bash
MOONBEAM_RPC_URL="https://rpc.api.moonbeam.network" forge test --match-contract PoCTest -vvv
```

The template uses `MOONBEAM_RPC_URL` environment variable. The public RPC requires a pinned block number (already hardcoded in setUp).

## In-Scope Contracts

| Contract | Address | Type |
|---|---|---|
| veNFT | `0xfa62B5962a7923A2910F945268AA65C943D131e9` | Direct (no proxy) |
| Algebra Vault Factory | `0x9B81835b2f7B51447D5E4C07Ae18f05dfe627150` | Direct (no proxy) |
| stGLMR Funds Manager | `0x3069A7955408D261069F7D4ed3eFdB9Ea8D95d7b` | ERC1967 Proxy |
| Voter | `0x091a177FbC5f493920c2e027eDc89658c1cED495` | UUPS Proxy |

## Chain

Moonbeam (Chain ID 1284). All contracts are deployed on Moonbeam mainnet.

## Key Tokens

- STELLA: `0x0E358838ce72d5e61E0018a2ffaC4bEC5F4c88d2`
- WGLMR: `0xAcc15dC74880C9944775448304B263D191c6077F`
- stGLMR: `0x7d7164cFAc019872a3890b686306a3B8c5c5Ba73`

## Cross-Contract Relationships

- veNFT.voter() == Voter proxy
- Voter.getVeStella() == veNFT
- AlgebraVaultFactory.voter() == Voter proxy
- FundsManager.ST_GLMR() == stGLMR token
- FundsManager uses Ledger proxies to delegate to Moonbeam collators

## Bug Bounty Rules (Immunefi)

- **Severity:** Critical ($1,000-$2,337), High ($1,000-$1,337)
- **Reward Token:** STELLA on Moonbeam
- **Vesting:** Critical vests monthly over 12 months; High over 6 months
- **PoC Required:** Yes
- **KYC:** Not required

## Writing Your PoC

1. Add your exploit logic inside `test_PoC()` in `test/PoC.t.sol`
2. Use `vm.prank()` / `vm.startPrank()` to impersonate addresses
3. Use `deal()` to set token balances for test accounts
4. The template already has typed references: `venft`, `algebraVaultFactory`, `fundsManager`, `voter`, `stella`, `wglmr`
5. Add additional interfaces to the top of the file if you need functions not already defined

## Gotchas

- The public Moonbeam RPC does not support archive queries without a pinned block number
- veNFT token IDs can be burned/withdrawn; don't assume any specific ID has an active lock
- FundsManager and Voter are behind proxies; always interact with the proxy address (already set up in template)
- Voter uses UUPS upgrade pattern with AccessControl roles
- stGLMR FundsManager uses a custom auth system (AuthManager + Roles)
- Epoch duration is 1 week; cool-down period is 1 hour at start/end of epoch
