(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-payment (err u102))
(define-constant err-invalid-bandwidth (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-expired (err u105))
(define-constant err-insufficient-bandwidth (err u106))

(define-map bandwidth-listings
  { listing-id: uint }
  { 
    provider: principal,
    bandwidth-gb: uint,
    price-per-gb: uint,
    expiry-block: uint,
    available: bool
  }
)

(define-map user-allocations
  { user: principal, listing-id: uint }
  {
    allocated-gb: uint,
    start-block: uint,
    duration-blocks: uint,
    total-paid: uint
  }
)

(define-map provider-stats
  { provider: principal }
  {
    total-listings: uint,
    total-earned: uint,
    total-bandwidth-sold: uint
  }
)

(define-map buyer-stats
  { buyer: principal }
  {
    total-purchases: uint,
    total-spent: uint,
    total-bandwidth-bought: uint
  }
)

(define-data-var next-listing-id uint u1)
(define-data-var platform-fee-rate uint u100)

(define-read-only (get-listing (listing-id uint))
  (map-get? bandwidth-listings { listing-id: listing-id })
)

(define-read-only (get-user-allocation (user principal) (listing-id uint))
  (map-get? user-allocations { user: user, listing-id: listing-id })
)

(define-read-only (get-provider-stats (provider principal))
  (default-to
    { total-listings: u0, total-earned: u0, total-bandwidth-sold: u0 }
    (map-get? provider-stats { provider: provider })
  )
)

(define-read-only (get-buyer-stats (buyer principal))
  (default-to
    { total-purchases: u0, total-spent: u0, total-bandwidth-bought: u0 }
    (map-get? buyer-stats { buyer: buyer })
  )
)

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (calculate-total-cost (bandwidth-gb uint) (price-per-gb uint))
  (let ((base-cost (* bandwidth-gb price-per-gb))
        (platform-fee (/ (* base-cost (var-get platform-fee-rate)) u10000)))
    (+ base-cost platform-fee)
  )
)

(define-read-only (is-listing-active (listing-id uint))
  (match (get-listing listing-id)
    listing (and 
              (get available listing)
              (> (get expiry-block listing) stacks-block-height))
    false
  )
)

(define-public (create-bandwidth-listing (bandwidth-gb uint) (price-per-gb uint) (duration-blocks uint))
  (let ((listing-id (var-get next-listing-id))
        (expiry-block (+ stacks-block-height duration-blocks)))
    (asserts! (> bandwidth-gb u0) err-invalid-bandwidth)
    (asserts! (> price-per-gb u0) err-invalid-bandwidth)
    (asserts! (> duration-blocks u0) err-invalid-bandwidth)
    
    (map-set bandwidth-listings
      { listing-id: listing-id }
      {
        provider: tx-sender,
        bandwidth-gb: bandwidth-gb,
        price-per-gb: price-per-gb,
        expiry-block: expiry-block,
        available: true
      }
    )
    
    (map-set provider-stats
      { provider: tx-sender }
      (let ((current-stats (get-provider-stats tx-sender)))
        {
          total-listings: (+ (get total-listings current-stats) u1),
          total-earned: (get total-earned current-stats),
          total-bandwidth-sold: (get total-bandwidth-sold current-stats)
        }
      )
    )
    
    (var-set next-listing-id (+ listing-id u1))
    (ok listing-id)
  )
)

(define-public (purchase-bandwidth (listing-id uint) (requested-gb uint) (duration-blocks uint))
  (let ((listing (unwrap! (get-listing listing-id) err-not-found))
        (total-cost (calculate-total-cost requested-gb (get price-per-gb listing)))
        (platform-fee (/ (* total-cost (var-get platform-fee-rate)) u10000))
        (provider-payment (- total-cost platform-fee)))
    
    (asserts! (is-listing-active listing-id) err-expired)
    (asserts! (<= requested-gb (get bandwidth-gb listing)) err-insufficient-bandwidth)
    (asserts! (> requested-gb u0) err-invalid-bandwidth)
    (asserts! (> duration-blocks u0) err-invalid-bandwidth)
    
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? provider-payment tx-sender (get provider listing))))
    
    (map-set user-allocations
      { user: tx-sender, listing-id: listing-id }
      {
        allocated-gb: requested-gb,
        start-block: stacks-block-height,
        duration-blocks: duration-blocks,
        total-paid: total-cost
      }
    )
    
    (map-set bandwidth-listings
      { listing-id: listing-id }
      (merge listing { bandwidth-gb: (- (get bandwidth-gb listing) requested-gb) })
    )
    
    (map-set provider-stats
      { provider: (get provider listing) }
      (let ((current-stats (get-provider-stats (get provider listing))))
        {
          total-listings: (get total-listings current-stats),
          total-earned: (+ (get total-earned current-stats) provider-payment),
          total-bandwidth-sold: (+ (get total-bandwidth-sold current-stats) requested-gb)
        }
      )
    )
    
    (map-set buyer-stats
      { buyer: tx-sender }
      (let ((current-stats (get-buyer-stats tx-sender)))
        {
          total-purchases: (+ (get total-purchases current-stats) u1),
          total-spent: (+ (get total-spent current-stats) total-cost),
          total-bandwidth-bought: (+ (get total-bandwidth-bought current-stats) requested-gb)
        }
      )
    )
    
    (ok true)
  )
)

(define-public (cancel-listing (listing-id uint))
  (let ((listing (unwrap! (get-listing listing-id) err-not-found)))
    (asserts! (is-eq tx-sender (get provider listing)) err-owner-only)
    
    (map-set bandwidth-listings
      { listing-id: listing-id }
      (merge listing { available: false })
    )
    
    (ok true)
  )
)

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-bandwidth)
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-public (withdraw-fees)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (as-contract (stx-transfer? (stx-get-balance tx-sender) tx-sender contract-owner)))
    (ok true)
  )
)
