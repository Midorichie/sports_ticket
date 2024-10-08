;; Sports Ticket Registry - Enhanced Implementation
;; Features advanced anti-scalping and dynamic pricing mechanisms

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TICKET-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PRICE (err u102))
(define-constant ERR-TRANSFER-LOCKED (err u103))
(define-constant ERR-IDENTITY-NOT-VERIFIED (err u104))
(define-constant ERR-COOLING-PERIOD (err u105))
(define-constant ERR-MAX-TRANSFER-REACHED (err u106))

;; Enhanced ticket data structure
(define-map tickets
    { ticket-id: uint }
    {
        owner: principal,
        event-id: uint,
        seat-info: (string-utf8 50),
        original-price: uint,
        current-price: uint,
        is-valid: bool,
        transfer-count: uint,
        last-transfer-time: uint,
        identity-verified: bool,
        transfer-lock: bool,
        price-floor: uint,
        price-ceiling: uint
    }
)

;; Enhanced events mapping
(define-map events
    { event-id: uint }
    {
        organizer: principal,
        total-tickets: uint,
        max-resale-markup: uint,
        event-date: uint,
        dynamic-pricing: bool,
        require-identity: bool,
        cooling-period: uint,
        max-transfers: uint,
        royalty-percentage: uint
    }
)

;; Price oracle data
(define-map price-points
    { event-id: uint }
    {
        base-price: uint,
        current-demand: uint,
        last-update: uint
    }
)

;; Identity verification mapping
(define-map verified-identities
    { user: principal }
    {
        verified: bool,
        verification-date: uint,
        verification-level: uint
    }
)

;; NFT implementation
(define-non-fungible-token sports-ticket uint)

;; Enhanced ticket issuance
(define-public (issue-ticket 
    (ticket-id uint)
    (event-id uint)
    (seat-info (string-utf8 50))
    (price uint)
    (recipient principal))
    (let
        (
            (event-exists (contract-call? .events get-event event-id))
            (identity-verified (get-identity-status recipient))
        )
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> price u0) ERR-INVALID-PRICE)
        (asserts! (or (not (get require-identity (unwrap! event-exists ERR-TICKET-NOT-FOUND)))
                     (get verified identity-verified))
                 ERR-IDENTITY-NOT-VERIFIED)
        
        ;; Calculate price bounds
        (let
            (
                (price-data (get-dynamic-price event-id price))
            )
            ;; Mint NFT and store enhanced ticket data
            (try! (nft-mint? sports-ticket ticket-id recipient))
            (map-set tickets
                { ticket-id: ticket-id }
                {
                    owner: recipient,
                    event-id: event-id,
                    seat-info: seat-info,
                    original-price: price,
                    current-price: price,
                    is-valid: true,
                    transfer-count: u0,
                    last-transfer-time: (unwrap! (get-block-info? time u0) ERR-TICKET-NOT-FOUND),
                    identity-verified: (get verified identity-verified),
                    transfer-lock: false,
                    price-floor: (get floor-price price-data),
                    price-ceiling: (get ceiling-price price-data)
                }
            )
            (ok true)
        )
    )
)

;; Enhanced transfer function with anti-scalping measures
(define-public (transfer-ticket
    (ticket-id uint)
    (recipient principal)
    (new-price uint))
    (let
        (
            (ticket (unwrap! (map-get? tickets {ticket-id: ticket-id}) ERR-TICKET-NOT-FOUND))
            (event (unwrap! (map-get? events {event-id: (get event-id ticket)}) ERR-TICKET-NOT-FOUND))
            (current-time (unwrap! (get-block-info? time u0) ERR-TICKET-NOT-FOUND))
        )
        ;; Enhanced validation checks
        (asserts! (is-eq (get owner ticket) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (not (get transfer-lock ticket)) ERR-TRANSFER-LOCKED)
        (asserts! (< (get transfer-count ticket) (get max-transfers event)) ERR-MAX-TRANSFER-REACHED)
        (asserts! (>= (- current-time (get last-transfer-time ticket)) 
                     (get cooling-period event)) 
                 ERR-COOLING-PERIOD)
        
        ;; Price validation
        (asserts! (and (>= new-price (get price-floor ticket))
                      (<= new-price (get price-ceiling ticket)))
                 ERR-INVALID-PRICE)
        
        ;; Calculate and distribute royalties
        (let
            (
                (royalty (/ (* new-price (get royalty-percentage event)) u100))
            )
            ;; Transfer NFT and update ticket data
            (try! (nft-transfer? sports-ticket ticket-id tx-sender recipient))
            ;; Send royalty to event organizer
            (try! (stx-transfer? royalty tx-sender (get organizer event)))
            
            ;; Update ticket data
            (map-set tickets
                { ticket-id: ticket-id }
                (merge ticket {
                    owner: recipient,
                    current-price: new-price,
                    transfer-count: (+ (get transfer-count ticket) u1),
                    last-transfer-time: current-time,
                    identity-verified: (get verified (unwrap! (map-get? verified-identities 
                                                                      {user: recipient})
                                                            ERR-IDENTITY-NOT-VERIFIED))
                })
            )
            (ok true)
        )
    )
)

;; Dynamic price calculation
(define-private (get-dynamic-price (event-id uint) (base-price uint))
    (let
        (
            (price-data (unwrap! (map-get? price-points {event-id: event-id})
                                {
                                    base-price: base-price,
                                    current-demand: u0,
                                    last-update: u0
                                }))
        )
        {
            floor-price: (/ (* base-price u75) u100),
            ceiling-price: (* base-price u2)
        }
    )
)

;; Identity verification check
(define-private (get-identity-status (user principal))
    (default-to 
        {
            verified: false,
            verification-date: u0,
            verification-level: u0
        }
        (map-get? verified-identities {user: user})
    )
)

;; Verify ticket with enhanced security
(define-public (verify-ticket (ticket-id uint))
    (let
        (
            (ticket (unwrap! (map-get? tickets {ticket-id: ticket-id}) ERR-TICKET-NOT-FOUND))
        )
        (ok {
            is-valid: (get is-valid ticket),
            owner: (get owner ticket),
            identity-verified: (get identity-verified ticket)
        })
    )
)

;; Lock ticket transfers (for emergency situations)
(define-public (lock-ticket-transfers (ticket-id uint))
    (let
        (
            (ticket (unwrap! (map-get? tickets {ticket-id: ticket-id}) ERR-TICKET-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (map-set tickets
            { ticket-id: ticket-id }
            (merge ticket { transfer-lock: true })
        )
        (ok true)
    )
)

;; Get enhanced ticket details
(define-read-only (get-ticket-details (ticket-id uint))
    (map-get? tickets {ticket-id: ticket-id})
)