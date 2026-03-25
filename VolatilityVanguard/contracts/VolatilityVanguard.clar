;; contract title: AI-Powered Liquidity Pool Fee Adjuster
;; <add a description here>
;; This contract manages a robust liquidity pool for Token X and Token Y.
;; It allows a decentralized network of authorized AI oracles to dynamically 
;; adjust swap fees based on real-time market volatility and trading volume analysis.
;; This dynamic adjustment protects Liquidity Providers (LPs) during periods of 
;; high market turbulence while remaining competitive during calm markets.
;; Features include:
;; - Dynamic fee adjustments bounded by strict min/max limits.
;; - Liquidity provision and removal with proportional LP token tracking.
;; - Protocol fee collection to sustain the ecosystem.
;; - Emergency pause functionality for extreme situations.
;; - Multi-oracle support for decentralized intelligence.

;; constants

;; Error definitions for strict access control and validation
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-FEE (err u101))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u102))
(define-constant ERR-PAUSED (err u103))
(define-constant ERR-ZERO-AMOUNT (err u104))
(define-constant ERR-SLIPPAGE-EXCEEDED (err u105))
(define-constant ERR-ORACLE-ALREADY-EXISTS (err u106))
(define-constant ERR-ORACLE-NOT-FOUND (err u107))
(define-constant ERR-COOLDOWN-ACTIVE (err u108))

;; The contract owner (deployer) who can update critical protocol settings
(define-constant CONTRACT-OWNER tx-sender)

;; Max fee allowed (e.g., 1000 basis points = 10%)
(define-constant MAX-FEE-BPS u1000)
;; Min fee allowed (e.g., 5 basis points = 0.05%)
(define-constant MIN-FEE-BPS u5)
;; Minimum time between AI fee updates (in blocks, roughly 1 hour if 1 block = 10 mins)
(define-constant UPDATE-COOLDOWN u6)

;; data maps and vars

;; The current total swap fee in basis points (default 30 bps = 0.3%)
(define-data-var current-fee-bps uint u30)

;; The protocol's share of the swap fee in basis points (default 5 bps)
(define-data-var protocol-fee-bps uint u5)

;; Emergency pause state for the entire contract
(define-data-var is-paused bool false)

;; Authorized AI oracles map (true means authorized)
(define-map authorized-oracles principal bool)

;; Liquidity pool reserves for Token X and Token Y
(define-data-var token-x-reserve uint u0)
(define-data-var token-y-reserve uint u0)

;; Protocol fee accumulated reserves
(define-data-var token-x-protocol-fees uint u0)
(define-data-var token-y-protocol-fees uint u0)

;; Mock LP Token state to track provider shares
(define-data-var total-lp-tokens uint u0)
(define-map lp-balances principal uint)

;; Record of historical fee updates by AI oracles
(define-map fee-history 
    { update-id: uint } 
    { oracle: principal, old-fee: uint, new-fee: uint, timestamp: uint, volatility-index: uint }
)
;; Auto-incrementing ID for the fee-history map
(define-data-var next-update-id uint u0)
;; Track the block height of the last fee update to enforce cooldowns
(define-data-var last-update-block uint u0)

;; private functions

;; Helper to verify if the caller is the contract owner
(define-private (is-owner (caller principal))
    (is-eq caller CONTRACT-OWNER)
)

;; Helper to verify if the contract is currently active
(define-private (check-active)
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (ok true)
    )
)

;; Helper to verify if the caller is an authorized AI oracle
(define-private (is-ai-oracle (caller principal))
    (default-to false (map-get? authorized-oracles caller))
)

;; Helper to calculate the amount of LP tokens to mint
;; Uses a proportional calculation based on existing reserves
(define-private (calc-lp-mint (amount-x uint) (amount-y uint) (res-x uint) (res-y uint) (total-lp uint))
    (if (is-eq total-lp u0)
        ;; Simplified initial mint calculation
        (/ (+ amount-x amount-y) u2)
        ;; Proportional mint for subsequent deposits
        (let (
            (share-x (/ (* amount-x total-lp) res-x))
            (share-y (/ (* amount-y total-lp) res-y))
        )
        (if (< share-x share-y) share-x share-y))
    )
)

;; Helper to calculate the output amount for a swap given the current fee
;; Uses the standard constant product formula: (x + dx) * (y - dy) = x * y
(define-private (calculate-swap-out (amount-in uint) (reserve-in uint) (reserve-out uint) (fee-bps uint))
    (let (
        (fee-amount (/ (* amount-in fee-bps) u10000))
        (amount-in-with-fee (- amount-in fee-amount))
        (numerator (* amount-in-with-fee reserve-out))
        (denominator (+ reserve-in amount-in-with-fee))
    )
    (/ numerator denominator))
)

;; public functions

;; ---------------------------------------------------------
;; Admin & Configuration Functions
;; ---------------------------------------------------------

;; Pause the contract (Emergency stop)
(define-public (pause-contract)
    (begin
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
        (ok (var-set is-paused true))
    )
)

;; Resume the contract
(define-public (resume-contract)
    (begin
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
        (ok (var-set is-paused false))
    )
)

;; Add a new authorized AI oracle
(define-public (add-oracle (new-oracle principal))
    (begin
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-ai-oracle new-oracle)) ERR-ORACLE-ALREADY-EXISTS)
        (ok (map-set authorized-oracles new-oracle true))
    )
)

;; Remove an authorized AI oracle
(define-public (remove-oracle (oracle principal))
    (begin
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-ai-oracle oracle) ERR-ORACLE-NOT-FOUND)
        (ok (map-delete authorized-oracles oracle))
    )
)

;; Set the protocol's share of the swap fee
(define-public (set-protocol-fee (new-protocol-fee-bps uint))
    (begin
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (< new-protocol-fee-bps (var-get current-fee-bps)) ERR-INVALID-FEE)
        (ok (var-set protocol-fee-bps new-protocol-fee-bps))
    )
)

;; ---------------------------------------------------------
;; Liquidity Provision Functions
;; ---------------------------------------------------------

;; Add liquidity to the pool and receive LP tokens
(define-public (add-liquidity (amount-x uint) (amount-y uint))
    (let (
        (res-x (var-get token-x-reserve))
        (res-y (var-get token-y-reserve))
        (total-lp (var-get total-lp-tokens))
        (lp-to-mint (calc-lp-mint amount-x amount-y res-x res-y total-lp))
        (current-lp-balance (default-to u0 (map-get? lp-balances tx-sender)))
    )
    (begin
        (try! (check-active))
        (asserts! (> amount-x u0) ERR-ZERO-AMOUNT)
        (asserts! (> amount-y u0) ERR-ZERO-AMOUNT)
        
        ;; Update reserves
        (var-set token-x-reserve (+ res-x amount-x))
        (var-set token-y-reserve (+ res-y amount-y))
        
        ;; Update LP tokens
        (var-set total-lp-tokens (+ total-lp lp-to-mint))
        (map-set lp-balances tx-sender (+ current-lp-balance lp-to-mint))
        
        (ok lp-to-mint)
    ))
)

;; Remove liquidity from the pool by burning LP tokens
(define-public (remove-liquidity (lp-amount uint))
    (let (
        (res-x (var-get token-x-reserve))
        (res-y (var-get token-y-reserve))
        (total-lp (var-get total-lp-tokens))
        (current-lp-balance (default-to u0 (map-get? lp-balances tx-sender)))
        (amount-x-out (/ (* lp-amount res-x) total-lp))
        (amount-y-out (/ (* lp-amount res-y) total-lp))
    )
    (begin
        (try! (check-active))
        (asserts! (> lp-amount u0) ERR-ZERO-AMOUNT)
        (asserts! (>= current-lp-balance lp-amount) ERR-INSUFFICIENT-LIQUIDITY)
        
        ;; Update reserves
        (var-set token-x-reserve (- res-x amount-x-out))
        (var-set token-y-reserve (- res-y amount-y-out))
        
        ;; Update LP tokens
        (var-set total-lp-tokens (- total-lp lp-amount))
        (map-set lp-balances tx-sender (- current-lp-balance lp-amount))
        
        (ok { amount-x: amount-x-out, amount-y: amount-y-out })
    ))
)

;; ---------------------------------------------------------
;; Swap Functions
;; ---------------------------------------------------------

;; Swap Token X for Token Y
(define-public (swap-x-for-y (amount-in uint) (min-amount-out uint))
    (let (
        (res-x (var-get token-x-reserve))
        (res-y (var-get token-y-reserve))
        (fee-bps (var-get current-fee-bps))
        (amount-out (calculate-swap-out amount-in res-x res-y fee-bps))
        (protocol-fee-amount (/ (* amount-in (var-get protocol-fee-bps)) u10000))
    )
    (begin
        (try! (check-active))
        (asserts! (> amount-in u0) ERR-ZERO-AMOUNT)
        (asserts! (>= amount-out min-amount-out) ERR-SLIPPAGE-EXCEEDED)
        (asserts! (< amount-out res-y) ERR-INSUFFICIENT-LIQUIDITY)
        
        ;; Update reserves (deducting protocol fee from the pool addition)
        (var-set token-x-reserve (+ res-x (- amount-in protocol-fee-amount)))
        (var-set token-y-reserve (- res-y amount-out))
        
        ;; Add to protocol fees
        (var-set token-x-protocol-fees (+ (var-get token-x-protocol-fees) protocol-fee-amount))
        
        (ok amount-out)
    ))
)

;; Swap Token Y for Token X
(define-public (swap-y-for-x (amount-in uint) (min-amount-out uint))
    (let (
        (res-x (var-get token-x-reserve))
        (res-y (var-get token-y-reserve))
        (fee-bps (var-get current-fee-bps))
        (amount-out (calculate-swap-out amount-in res-y res-x fee-bps))
        (protocol-fee-amount (/ (* amount-in (var-get protocol-fee-bps)) u10000))
    )
    (begin
        (try! (check-active))
        (asserts! (> amount-in u0) ERR-ZERO-AMOUNT)
        (asserts! (>= amount-out min-amount-out) ERR-SLIPPAGE-EXCEEDED)
        (asserts! (< amount-out res-x) ERR-INSUFFICIENT-LIQUIDITY)
        
        ;; Update reserves (deducting protocol fee from the pool addition)
        (var-set token-y-reserve (+ res-y (- amount-in protocol-fee-amount)))
        (var-set token-x-reserve (- res-x amount-out))
        
        ;; Add to protocol fees
        (var-set token-y-protocol-fees (+ (var-get token-y-protocol-fees) protocol-fee-amount))
        
        (ok amount-out)
    ))
)

;; Read-only function to get the current fee
(define-read-only (get-current-fee)
    (ok (var-get current-fee-bps))
)

;; ---------------------------------------------------------
;; AI Oracle Fee Adjustment Function (Newly Added Feature)
;; ---------------------------------------------------------
;; This function is exclusively called by authorized AI oracles.
;; It analyzes off-chain volatility data and submits a new 
;; optimal fee rate to protect liquidity providers from impermanent loss.
;; It includes a cooldown mechanism to prevent fee thrashing
;; and logs the update in the fee-history map for transparency.
;; The AI considers the volatility index and overall market trend to set fees.
(define-public (adjust-fee-based-on-volatility (new-fee-bps uint) (volatility-index uint) (market-trend (string-ascii 10)))
    (let (
        (current-id (var-get next-update-id))
        (old-fee (var-get current-fee-bps))
        (current-block block-height)
        (last-update (var-get last-update-block))
    )
    (begin
        ;; Security Check 1: Ensure contract is not paused
        (try! (check-active))
        
        ;; Security Check 2: Ensure caller is an authorized AI Oracle
        (asserts! (is-ai-oracle tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Security Check 3: Ensure fee is within safe bounds to prevent malicious or erroneous spikes
        (asserts! (<= new-fee-bps MAX-FEE-BPS) ERR-INVALID-FEE)
        (asserts! (>= new-fee-bps MIN-FEE-BPS) ERR-INVALID-FEE)
        
        ;; Security Check 4: Enforce cooldown period to prevent rapid fee manipulation
        (asserts! (>= current-block (+ last-update UPDATE-COOLDOWN)) ERR-COOLDOWN-ACTIVE)
        
        ;; Update the current fee variable
        (var-set current-fee-bps new-fee-bps)
        
        ;; Update the last modified block
        (var-set last-update-block current-block)
        
        ;; Record the historical update for auditing and on-chain analytics
        (map-set fee-history 
            { update-id: current-id } 
            { 
                oracle: tx-sender,
                old-fee: old-fee,
                new-fee: new-fee-bps, 
                timestamp: current-block, 
                volatility-index: volatility-index 
            }
        )
        
        ;; Increment the update ID for the next adjustment
        (var-set next-update-id (+ current-id u1))
        
        ;; Emit success with rich metadata
        (ok {
            success: true,
            update-id: current-id,
            new-fee: new-fee-bps,
            trend-logged: market-trend
        })
    ))
)


