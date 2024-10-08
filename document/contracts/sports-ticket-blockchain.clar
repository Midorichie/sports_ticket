;; Sports Ticket Registry - Initial Implementation
;; Handles ticket issuance, transfers, and verification

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TICKET-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PRICE (err u102))

;; Define the ticket data structure
(define-map tickets
    { ticket-id: uint }
    {
        owner: principal,
        event-id: uint,
        seat-info: (string-utf8 50),
        original-price: uint,
        current-price: uint,
        is-valid: bool,
        transfer-count: uint
    }
)

;; Keep track of events
(define-map events
    { event-id: uint }
    {
        organizer: principal,
        total-tickets: uint,
        max-resale-markup: uint,
        event-date: uint
    }
)

;; NFT implementation for tickets
(define-non-fungible-token sports-ticket uint)

;; Issue new ticket
(define-public (issue-ticket 
    (ticket-id uint)
    (event-id uint)
    (seat-info (string-utf8 50))
    (price uint)
    (recipient principal))
    (let
        (
            (event-exists (contract-call? .events get-event event-id))
        )
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> price u0) ERR-INVALID-PRICE)
        
        ;; Mint NFT and store ticket data
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
                transfer-count: u0
            }
        )
        (ok true)
    )
)

;; Transfer ticket
(define-public (transfer-ticket
    (ticket-id uint)
    (recipient principal)
    (new-price uint))
    (let
        (
            (ticket (unwrap! (map-get? tickets {ticket-id: ticket-id}) ERR-TICKET-NOT-FOUND))
            (event (unwrap! (map-get? events {event-id: (get event-id ticket)}) ERR-TICKET-NOT-FOUND))
        )
        (asserts! (is-eq (get owner ticket) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-price (+ (get original-price ticket) 
            (* (get original-price ticket) (/ (get max-resale-markup event) u100)))) 
            ERR-INVALID-PRICE)
        
        ;; Transfer NFT and update ticket data
        (try! (nft-transfer? sports-ticket ticket-id tx-sender recipient))
        (map-set tickets
            { ticket-id: ticket-id }
            (merge ticket {
                owner: recipient,
                current-price: new-price,
                transfer-count: (+ (get transfer-count ticket) u1)
            })
        )
        (ok true)
    )
)

;; Verify ticket
(define-public (verify-ticket (ticket-id uint))
    (let
        (
            (ticket (unwrap! (map-get? tickets {ticket-id: ticket-id}) ERR-TICKET-NOT-FOUND))
        )
        (ok (get is-valid ticket))
    )
)

;; Get ticket details
(define-read-only (get-ticket (ticket-id uint))
    (map-get? tickets {ticket-id: ticket-id})
)