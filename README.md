# Lelangfi — Vehicle Auction Smart Contracts

A decentralized vehicle auction platform on EVM, built with Solidity and Foundry.

## Overview

Lelang enables trusted vehicle auctions with NFT ownership tracking, USDC settlement, and a dispute resolution mechanism. Key features:

- **Seller & Validator Whitelist** — AccessControl-based registration.
- **Vehicle Listings** — On-chain metadata + off-chain verification flow.
- **Per-Listing Auction Contract** — Factory-deployed, isolated auction instances.
- **Collateral-backed Bidding** — 10% collateral, 5% minimum bid increment, anti-snipe extension.
- **Cascade Mechanism** — If winner defaults, next highest bidder gets an offer (accept/decline/slash cycle).
- **NFT Ownership** — Soulbound VehicleOwnershipNFT minted on payment, transferable after delivery.
- **Dispute Resolution** — Validator-mediated escrow release.
- **Delivery Timeout** — Buyer can force-refund after 30 days if seller never confirms shipment.

## Contracts

| Contract                 | Description                                              |
| ------------------------ | -------------------------------------------------------- |
| `SellerRegistry`         | Seller whitelist (admin-managed)                         |
| `ValidatorRegistry`      | Validator whitelist (admin-managed)                      |
| `VehicleListingRegistry` | Listing submission, approval, rejection                  |
| `VehicleOwnershipNFT`    | ERC-721 soulbound NFT with transferable flag             |
| `VehicleAuction`         | Core auction logic (bid, pay, confirm, cascade, dispute) |
| `VehicleAuctionFactory`  | Deploys one `VehicleAuction` per listing                 |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/)
- USDC token contract address (6 decimals)

## Quick Start

```bash
# Install dependencies
forge install

# Build
forge build --via-ir

# Test
forge test --via-ir -vvv --match-path "test/*.t.sol"
```

## Deploy

Set environment variables in `.env`, then run:

```bash
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Required env vars: `RPC_URL`, `PRIVATE_KEY`, `DEPLOYER_PRIVATE_KEY`, `USDC_TOKEN`, `TREASURY` (optional, defaults to deployer).

## Configuration Defaults

| Parameter            | Value      |
| -------------------- | ---------- |
| Platform fee         | 2.5%       |
| Collateral           | 10% of bid |
| Min bid increment    | 5%         |
| Anti-snipe extension | 10 minutes |
| Payment window       | 3 days     |
| Dispute window       | 14 days    |
| Delivery timeout     | 30 days    |

## Architecture

```
Factory ──deploys──► per-listing Auction ──uses──► ListingRegistry
                          │                            ▲
                          ▼                            │
                     VehicleOwnershipNFT          SellerRegistry
                          │                     ValidatorRegistry
                          ▼
                      USDC (external)
```

## Test Suites (60 tests, all passing)

```bash
forge test --via-ir -vvv --match-path "test/*.t.sol"
```

| Test File                      | Tests | Focus |
| ------------------------------ | ----- | ----- |
| `SellerRegistry.t.sol`         | 9     | Seller whitelist CRUD |
| `ValidatorRegistry.t.sol`      | 8     | Validator whitelist CRUD |
| `VehicleListingRegistry.t.sol` | 9     | Listing submit/approve/reject |
| `VehicleAuction.t.sol`         | 23    | Bidding, payment, delivery, dispute, force-refund |
| `CascadingOffer.t.sol`         | 11    | Winner kabur, cascade, accept/decline/slash |

## Remaining Improvements

Minor issues identified but not yet implemented (pending decision):

- `_returnAllCollateral()` uses O(n) unbounded loop — consider pull-over-push pattern
- No `Pausable` / emergency stop mechanism
- No upgradeability (no proxy pattern)
- `startPaymentPhase()` open to any caller
- Registry addresses immutable per auction (no migration path)
- Critical config constants hardcoded (`EXTEND_WINDOW`, `DISPUTE_WINDOW`, `DELIVERY_TIMEOUT`)
