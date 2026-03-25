# VolatilityVanguard

The **VolatilityVanguard** protocol is a sophisticated, AI-driven Decentralized Exchange (DEX) liquidity pool implementation written in Clarity for the Stacks blockchain. It represents a paradigm shift in Automated Market Maker (AMM) design by integrating off-chain intelligence with on-chain execution to mitigate Impermanent Loss (IL) and maximize Liquidity Provider (LP) returns.

---

## Table of Contents
* Introduction
* Core Philosophy
* Architecture Overview
* Detailed Function Specifications
    * Private Helper Functions
    * Administrative & Configuration Functions
    * Liquidity Provision Functions
    * Swap Operations
    * AI Oracle Fee Adjustment
    * Read-Only Data Accessors
* Security Mechanisms
* Error Code Reference
* Constants & Parameters
* Contribution Guidelines
* License Information

---

## Introduction

In traditional AMMs, swap fees are typically static (e.g., 0.3%). During periods of extreme market volatility, these static fees often fail to compensate Liquidity Providers for the risks of toxic flow and arbitrage-induced impermanent loss. **VolatilityVanguard** solves this by introducing a decentralized network of authorized AI Oracles. These oracles analyze real-time market trends, volatility indices, and volume data off-chain to dynamically adjust the pool's fee structure within safe, pre-defined bounds.

## Core Philosophy

I designed this contract to balance decentralization with defensive automation. The primary goal is to ensure that the pool remains competitive during "calm" markets with low fees to attract volume, while automatically "thickening" the fee barrier during "turbulent" markets to protect the underlying capital of the providers.



---

## Architecture Overview

The system consists of three primary layers:
1.  **The Capital Layer:** Manages the actual Token X and Token Y reserves and the proportional minting/burning of LP tokens.
2.  **The Intelligence Layer:** A registry of authorized AI Oracles that can submit fee updates based on external data.
3.  **The Safety Layer:** A suite of constants, cooldowns, and emergency pauses that ensure the AI cannot behave erratically or be exploited.

---

## Detailed Function Specifications

### Private Helper Functions
These functions are internal to the contract logic and cannot be called directly by external users.

* **`is-owner (caller principal)`**: Returns a boolean indicating if the provided principal is the contract deployer.
* **`check-active`**: A guard function that asserts the contract is not in a paused state.
* **`is-ai-oracle (caller principal)`**: Checks the `authorized-oracles` map to verify if a caller has the permissions to adjust fees.
* **`calc-lp-mint (amount-x uint) (amount-y uint) (res-x uint) (res-y uint) (total-lp uint)`**: Implements the proportional math for liquidity shares. If the pool is empty, it uses a simplified mean; otherwise, it ensures the depositor receives a share equal to the lesser of the two token ratios provided to prevent pool diluting.
* **`calculate-swap-out (amount-in uint) (reserve-in uint) (reserve-out uint) (fee-bps uint)`**: Implements the Constant Product Formula $x \times y = k$. It first deducts the dynamic fee from the input amount before calculating the output to be sent to the trader.

### Administrative & Configuration Functions
Restricted to the `CONTRACT-OWNER`.

* **`pause-contract`**: Sets the emergency stop flag to `true`, halting all swaps and liquidity movements.
* **`resume-contract`**: Re-activates the protocol.
* **`add-oracle (new-oracle principal)`**: Whitelists a new AI oracle address.
* **`remove-oracle (oracle principal)`**: Revokes an AI oracle's authority.
* **`set-protocol-fee (new-protocol-fee-bps uint)`**: Adjusts the portion of the fee diverted to the protocol treasury. It must always be lower than the current total fee.

### Liquidity Provision Functions
Open to all users when the contract is active.

* **`add-liquidity (amount-x uint) (amount-y uint)`**: Users deposit a pair of tokens. The contract calculates the `lp-to-mint`, updates reserves, and increments the user's balance in the `lp-balances` map.
* **`remove-liquidity (lp-amount uint)`**: Users burn their LP tokens to receive a proportional share of the current `token-x-reserve` and `token-y-reserve`.

### Swap Operations
The engine of the DEX.

* **`swap-x-for-y (amount-in uint) (min-amount-out uint)`**: Swaps Token X for Token Y. It incorporates slippage protection via `min-amount-out` and automatically diverts the `protocol-fee-bps` to the protocol reserves.
* **`swap-y-for-x (amount-in uint) (min-amount-out uint)`**: The inverse swap. Both functions utilize the dynamic `current-fee-bps` set by the AI oracles.

### AI Oracle Fee Adjustment
The signature feature of VolatilityVanguard.

* **`adjust-fee-based-on-volatility (new-fee-bps uint) (volatility-index uint) (market-trend (string-ascii 10))`**: Called by AI Oracles. It validates the new fee against `MAX-FEE-BPS` and `MIN-FEE-BPS`, ensures the `UPDATE-COOLDOWN` has passed since the last change, and records the `volatility-index` and `market-trend` for historical auditability.

### Read-Only Data Accessors
Publicly accessible without gas fees (off-chain).

* **`get-current-fee`**: Returns the current basis points being charged for swaps.
* **`get-reserves`**: (Implicitly accessible via data-vars) Provides visibility into pool depth.

---

## Security Mechanisms

I have implemented several "Circuit Breakers" to ensure protocol integrity:
1.  **Fee Bounding:** No AI Oracle can set a fee higher than 10% or lower than 0.05%, preventing both "vampire" fee attacks and "zero-fee" exhaustion attacks.
2.  **Temporal Cooldown:** The `UPDATE-COOLDOWN` (default 6 blocks) prevents high-frequency manipulation of the fee rate within a single block or short window.
3.  **Slippage Checks:** Users must provide a `min-amount-out` to protect themselves from front-running or drastic price shifts during execution.
4.  **Decentralized Intelligence:** By supporting multiple oracles, the protocol can move toward a consensus-based AI model rather than a single point of failure.

---

## Error Code Reference

| Error Code | Constant | Description |
| :--- | :--- | :--- |
| `u100` | `ERR-NOT-AUTHORIZED` | Caller does not have required permissions. |
| `u101` | `ERR-INVALID-FEE` | Fee is outside of 5-1000 bps range or logic is flawed. |
| `u102` | `ERR-INSUFFICIENT-LIQUIDITY` | Request exceeds pool reserves. |
| `u103` | `ERR-PAUSED` | Contract is in emergency pause mode. |
| `u104` | `ERR-ZERO-AMOUNT` | Input amounts must be greater than zero. |
| `u105` | `ERR-SLIPPAGE-EXCEEDED` | Output amount is less than user's minimum requirement. |
| `u106` | `ERR-ORACLE-ALREADY-EXISTS` | Attempting to add an already whitelisted oracle. |
| `u107` | `ERR-ORACLE-NOT-FOUND` | Attempting to remove a non-existent oracle. |
| `u108` | `ERR-COOLDOWN-ACTIVE` | AI update attempted before cooldown period elapsed. |

---

## Constants & Parameters

* **MAX-FEE-BPS:** `u1000` (10.00%)
* **MIN-FEE-BPS:** `u5` (0.05%)
* **UPDATE-COOLDOWN:** `u6` blocks (~1 hour)
* **Default Fee:** `u30` (0.30%)

---

## Contribution Guidelines

I welcome contributions from the community to enhance the AI logic and pool efficiency.
1.  Fork the repository.
2.  Create a feature branch for your improvement (e.g., `feature/weighted-oracle-consensus`).
3.  Ensure all Clarity unit tests pass using the Clarinet framework.
4.  Submit a Pull Request with a detailed description of changes.

---

## License Information

### MIT License

Copyright (c) 2026 VolatilityVanguard Protocol Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---
