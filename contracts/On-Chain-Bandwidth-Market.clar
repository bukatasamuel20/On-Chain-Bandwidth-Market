(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-payment (err u102))
(define-constant err-invalid-bandwidth (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-expired (err u105))
(define-constant err-insufficient-bandwidth (err u106))

(define-constant err-subscription-exists (err u107))
(define-constant err-subscription-inactive (err u108))
(define-constant err-renewal-too-early (err u109))

(define-constant err-self-referral (err u120))
(define-constant err-referrer-exists (err u121))

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


(define-map bandwidth-subscriptions
  { subscription-id: uint }
  {
    subscriber: principal,
    provider: principal,
    bandwidth-gb: uint,
    price-per-gb: uint,
    renewal-blocks: uint,
    next-renewal-block: uint,
    active: bool,
    auto-renew: bool
  }
)

(define-map subscription-history
  { subscriber: principal, provider: principal }
  {
    total-renewals: uint,
    total-paid: uint,
    current-subscription-id: (optional uint)
  }
)

(define-data-var next-subscription-id uint u1)

(define-read-only (get-subscription (subscription-id uint))
  (map-get? bandwidth-subscriptions { subscription-id: subscription-id })
)

(define-read-only (get-subscription-history (subscriber principal) (provider principal))
  (default-to
    { total-renewals: u0, total-paid: u0, current-subscription-id: none }
    (map-get? subscription-history { subscriber: subscriber, provider: provider })
  )
)

(define-read-only (is-renewal-due (subscription-id uint))
  (match (get-subscription subscription-id)
    subscription (and 
                   (get active subscription)
                   (<= (get next-renewal-block subscription) stacks-block-height))
    false
  )
)

(define-public (create-subscription (provider principal) (bandwidth-gb uint) (price-per-gb uint) (renewal-blocks uint))
  (let ((subscription-id (var-get next-subscription-id))
        (next-renewal (+ stacks-block-height renewal-blocks))
        (total-cost (calculate-total-cost bandwidth-gb price-per-gb)))
    
    (asserts! (> bandwidth-gb u0) err-invalid-bandwidth)
    (asserts! (> price-per-gb u0) err-invalid-bandwidth)
    (asserts! (> renewal-blocks u100) err-invalid-bandwidth)
    
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    
    (map-set bandwidth-subscriptions
      { subscription-id: subscription-id }
      {
        subscriber: tx-sender,
        provider: provider,
        bandwidth-gb: bandwidth-gb,
        price-per-gb: price-per-gb,
        renewal-blocks: renewal-blocks,
        next-renewal-block: next-renewal,
        active: true,
        auto-renew: true
      }
    )
    
    (map-set subscription-history
      { subscriber: tx-sender, provider: provider }
      (let ((history (get-subscription-history tx-sender provider)))
        {
          total-renewals: (+ (get total-renewals history) u1),
          total-paid: (+ (get total-paid history) total-cost),
          current-subscription-id: (some subscription-id)
        }
      )
    )
    
    (var-set next-subscription-id (+ subscription-id u1))
    (ok subscription-id)
  )
)

(define-public (renew-subscription (subscription-id uint))
  (let ((subscription (unwrap! (get-subscription subscription-id) err-not-found))
        (total-cost (calculate-total-cost (get bandwidth-gb subscription) (get price-per-gb subscription))))
    
    (asserts! (get active subscription) err-subscription-inactive)
    (asserts! (is-renewal-due subscription-id) err-renewal-too-early)
    
    (try! (stx-transfer? total-cost (get subscriber subscription) (as-contract tx-sender)))
    
    (map-set bandwidth-subscriptions
      { subscription-id: subscription-id }
      (merge subscription { 
        next-renewal-block: (+ (get next-renewal-block subscription) (get renewal-blocks subscription))
      })
    )
    
    (map-set subscription-history
      { subscriber: (get subscriber subscription), provider: (get provider subscription) }
      (let ((history (get-subscription-history (get subscriber subscription) (get provider subscription))))
        {
          total-renewals: (+ (get total-renewals history) u1),
          total-paid: (+ (get total-paid history) total-cost),
          current-subscription-id: (get current-subscription-id history)
        }
      )
    )
    
    (ok true)
  )
)

(define-public (toggle-auto-renew (subscription-id uint))
  (let ((subscription (unwrap! (get-subscription subscription-id) err-not-found)))
    (asserts! (is-eq tx-sender (get subscriber subscription)) err-owner-only)
    
    (map-set bandwidth-subscriptions
      { subscription-id: subscription-id }
      (merge subscription { auto-renew: (not (get auto-renew subscription)) })
    )
    
    (ok true)
  )
)

(define-public (cancel-subscription (subscription-id uint))
  (let ((subscription (unwrap! (get-subscription subscription-id) err-not-found)))
    (asserts! (is-eq tx-sender (get subscriber subscription)) err-owner-only)
    
    (map-set bandwidth-subscriptions
      { subscription-id: subscription-id }
      (merge subscription { active: false })
    )
    
    (ok true)
  )
)

(define-map user-referrers
  { user: principal }
  { referrer: principal }
)

(define-constant referral-share-bps u5000)

(define-read-only (get-referrer (user principal))
  (map-get? user-referrers { user: user })
)

(define-public (set-referrer (referrer principal))
  (begin
    (asserts! (not (is-eq tx-sender referrer)) err-self-referral)
    (asserts! (is-none (map-get? user-referrers { user: tx-sender })) err-referrer-exists)
    (map-set user-referrers { user: tx-sender } { referrer: referrer })
    (ok true)
  )
)

(define-public (purchase-with-referral (listing-id uint) (requested-gb uint) (duration-blocks uint))
  (let (
        (listing (unwrap! (get-listing listing-id) err-not-found))
        (total-cost (calculate-total-cost requested-gb (get price-per-gb listing)))
        (platform-fee (/ (* total-cost (var-get platform-fee-rate)) u10000))
        (provider-payment (- total-cost platform-fee))
        (ref-opt (map-get? user-referrers { user: tx-sender }))
      )
    (asserts! (is-listing-active listing-id) err-expired)
    (asserts! (<= requested-gb (get bandwidth-gb listing)) err-insufficient-bandwidth)
    (asserts! (> requested-gb u0) err-invalid-bandwidth)
    (asserts! (> duration-blocks u0) err-invalid-bandwidth)

    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? provider-payment tx-sender (get provider listing))))

    (match ref-opt
      ref-data
        (begin
          (let ((reward (/ (* platform-fee referral-share-bps) u10000)))
            (try! (as-contract (stx-transfer? reward tx-sender (get referrer ref-data)))))
          true)
      true
    )

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
      (let ((ps (get-provider-stats (get provider listing))))
        {
          total-listings: (get total-listings ps),
          total-earned: (+ (get total-earned ps) provider-payment),
          total-bandwidth-sold: (+ (get total-bandwidth-sold ps) requested-gb)
        }
      )
    )

    (map-set buyer-stats
      { buyer: tx-sender }
      (let ((bs (get-buyer-stats tx-sender)))
        {
          total-purchases: (+ (get total-purchases bs) u1),
          total-spent: (+ (get total-spent bs) total-cost),
          total-bandwidth-bought: (+ (get total-bandwidth-bought bs) requested-gb)
        }
      )
    )
    (ok true)
  )
)