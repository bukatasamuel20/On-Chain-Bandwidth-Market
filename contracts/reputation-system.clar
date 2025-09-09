(define-constant err-already-rated (err u110))
(define-constant err-invalid-rating (err u111))
(define-constant err-unauthorized-rater (err u112))

(define-map provider-reputation
  { provider: principal }
  {
    total-score: uint,
    total-ratings: uint,
    reliability-score: uint,
    performance-score: uint,
    uptime-percentage: uint,
    completed-orders: uint,
    failed-orders: uint
  }
)

(define-map service-ratings
  { buyer: principal, provider: principal, transaction-id: uint }
  {
    quality-rating: uint,
    speed-rating: uint,
    reliability-rating: uint,
    timestamp: uint,
    rated: bool
  }
)

(define-map provider-performance-log
  { provider: principal, block-height: uint }
  {
    uptime-reported: uint,
    response-time-ms: uint,
    bandwidth-delivered: uint,
    service-issues: uint
  }
)

(define-data-var rating-window-blocks uint u1440)

(define-read-only (get-provider-reputation (provider principal))
  (default-to
    { total-score: u0, total-ratings: u0, reliability-score: u0, performance-score: u0, 
      uptime-percentage: u10000, completed-orders: u0, failed-orders: u0 }
    (map-get? provider-reputation { provider: provider })
  )
)

(define-read-only (get-service-rating (buyer principal) (provider principal) (transaction-id uint))
  (map-get? service-ratings { buyer: buyer, provider: provider, transaction-id: transaction-id })
)

(define-read-only (calculate-reputation-score (provider principal))
  (let ((reputation (get-provider-reputation provider)))
    (if (is-eq (get total-ratings reputation) u0)
      u0
      (/ (get total-score reputation) (get total-ratings reputation))
    )
  )
)

(define-read-only (get-provider-reliability-rating (provider principal))
  (let ((reputation (get-provider-reputation provider))
        (total-orders (+ (get completed-orders reputation) (get failed-orders reputation))))
    (if (is-eq total-orders u0)
      u10000
      (/ (* (get completed-orders reputation) u10000) total-orders)
    )
  )
)

(define-public (submit-service-rating (provider principal) (transaction-id uint) (quality uint) (speed uint) (reliability uint))
  (let ((rating-key { buyer: tx-sender, provider: provider, transaction-id: transaction-id }))
    (asserts! (and (<= quality u5) (>= quality u1)) err-invalid-rating)
    (asserts! (and (<= speed u5) (>= speed u1)) err-invalid-rating)
    (asserts! (and (<= reliability u5) (>= reliability u1)) err-invalid-rating)
    (asserts! (is-none (get-service-rating tx-sender provider transaction-id)) err-already-rated)
    
    (map-set service-ratings rating-key
      {
        quality-rating: quality,
        speed-rating: speed,
        reliability-rating: reliability,
        timestamp: stacks-block-height,
        rated: true
      }
    )
    
    (let ((current-reputation (get-provider-reputation provider))
          (average-rating (/ (+ quality speed reliability) u3)))
      (map-set provider-reputation { provider: provider }
        {
          total-score: (+ (get total-score current-reputation) average-rating),
          total-ratings: (+ (get total-ratings current-reputation) u1),
          reliability-score: (get reliability-score current-reputation),
          performance-score: (get performance-score current-reputation),
          uptime-percentage: (get uptime-percentage current-reputation),
          completed-orders: (+ (get completed-orders current-reputation) u1),
          failed-orders: (get failed-orders current-reputation)
        }
      )
    )
    (ok true)
  )
)
