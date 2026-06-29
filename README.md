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

Required env vars: `RPC_URL`, `PRIVATE_KEY`, `USDC_ADDRESS`, `TREASURY_ADDRESS`, `PLATFORM_FEE_BPS`, `AUCTION_DURATION`, `COLLATERAL_BPS`, `MIN_INCREMENT_BPS`, `ANTI_SNIPE_EXTENSION`, `PAYMENT_WINDOW`, `DISPUTE_WINDOW`.

## Configuration Defaults


| Parameter            | Value      |
| -------------------- | ---------- |
| Platform fee         | 2.5%       |
| Collateral           | 10% of bid |
| Min bid increment    | 5%         |
| Anti-snipe extension | 10 minutes |
| Payment window       | 3 days     |
| Dispute window       | 14 days    |




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



## Test Suites (49 tests, all passing)

```bash
forge test --via-ir -vvv --match-path "test/*.t.sol"
```

- `SellerRegistry.t.sol` — 9 tests
- `VehicleListingRegistry.t.sol` — 9 tests
- `VehicleAuction.t.sol` — 20 tests (happy path, bids, disputes, NFT lifecycle, anti-snipe)
- `CascadingOffer.t.sol` — 11 tests (winner kabur, cascade, accept/decline/slash)

