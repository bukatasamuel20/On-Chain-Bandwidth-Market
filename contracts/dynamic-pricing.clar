(define-constant err-invalid-parameters (err u200))
(define-constant err-unauthorized (err u201))
(define-constant err-price-floor-exceeded (err u202))
(define-constant err-no-price-data (err u203))

(define-map dynamic-pricing-zones
  { zone-id: uint }
  {
    provider: principal,
    base-price-per-gb: uint,
    price-floor: uint,
    price-ceiling: uint,
    demand-multiplier: uint,
    last-update-block: uint,
    active: bool
  }
)

(define-map demand-signals
  { zone-id: uint, block-window: uint }
  {
    total-demand-gb: uint,
    unique-buyers: uint,
    average-purchase-size: uint,
    signal-strength: uint
  }
)

(define-map price-history
  { zone-id: uint, block-height: uint }
  {
    effective-price: uint,
    demand-level: uint,
    supply-available: uint
  }
)

(define-data-var next-zone-id uint u1)
(define-data-var price-update-interval uint u10)

(define-read-only (get-pricing-zone (zone-id uint))
  (map-get? dynamic-pricing-zones { zone-id: zone-id })
)

(define-read-only (get-demand-signal (zone-id uint) (block-window uint))
  (default-to
    { total-demand-gb: u0, unique-buyers: u0, average-purchase-size: u0, signal-strength: u0 }
    (map-get? demand-signals { zone-id: zone-id, block-window: block-window })
  )
)

(define-read-only (calculate-dynamic-price (zone-id uint) (requested-gb uint))
  (match (get-pricing-zone zone-id)
    zone
      (let ((current-window (/ stacks-block-height (var-get price-update-interval)))
            (demand (get-demand-signal zone-id current-window))
            (demand-factor (+ u10000 (* (get signal-strength demand) u100)))
            (calculated-price (/ (* (get base-price-per-gb zone) demand-factor) u10000)))
        (ok (if (> calculated-price (get price-ceiling zone))
              (get price-ceiling zone)
              (if (< calculated-price (get price-floor zone))
                (get price-floor zone)
                calculated-price))))
    err-no-price-data
  )
)

(define-public (create-pricing-zone (base-price uint) (floor-price uint) (ceiling-price uint))
  (let ((zone-id (var-get next-zone-id)))
    (asserts! (> base-price u0) err-invalid-parameters)
    (asserts! (>= base-price floor-price) err-invalid-parameters)
    (asserts! (<= base-price ceiling-price) err-invalid-parameters)
    (asserts! (< floor-price ceiling-price) err-invalid-parameters)
    
    (map-set dynamic-pricing-zones { zone-id: zone-id }
      {
        provider: tx-sender,
        base-price-per-gb: base-price,
        price-floor: floor-price,
        price-ceiling: ceiling-price,
        demand-multiplier: u10000,
        last-update-block: stacks-block-height,
        active: true
      }
    )
    
    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

(define-public (record-demand (zone-id uint) (bandwidth-gb uint))
  (let ((current-window (/ stacks-block-height (var-get price-update-interval)))
        (current-demand (get-demand-signal zone-id current-window)))
    (asserts! (> bandwidth-gb u0) err-invalid-parameters)
  
    (map-set demand-signals { zone-id: zone-id, block-window: current-window }
      {
        total-demand-gb: (+ (get total-demand-gb current-demand) bandwidth-gb),
        unique-buyers: (+ (get unique-buyers current-demand) u1),
        average-purchase-size: (/ (+ (get total-demand-gb current-demand) bandwidth-gb) 
                                   (+ (get unique-buyers current-demand) u1)),
        signal-strength: (let ((raw-strength (/ (+ (get total-demand-gb current-demand) bandwidth-gb) u10)))
                            (if (> raw-strength u100) u100 raw-strength))
      }
    )
    (ok true)
  )
)

(define-public (update-pricing-bounds (zone-id uint) (new-floor uint) (new-ceiling uint))
  (match (get-pricing-zone zone-id)
    zone
      (begin
        (asserts! (is-eq tx-sender (get provider zone)) err-unauthorized)
        (asserts! (< new-floor new-ceiling) err-invalid-parameters)
        (map-set dynamic-pricing-zones { zone-id: zone-id }
          (merge zone { price-floor: new-floor, price-ceiling: new-ceiling })
        )
        (ok true))
    err-no-price-data
  )
)
