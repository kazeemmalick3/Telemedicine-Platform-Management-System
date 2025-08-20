;; Provider Licensing Contract
;; Manages healthcare provider registration, licensing verification, and credential management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROVIDER-NOT-FOUND (err u101))
(define-constant ERR-INVALID-LICENSE (err u102))
(define-constant ERR-LICENSE-EXPIRED (err u103))
(define-constant ERR-ALREADY-REGISTERED (err u104))
(define-constant ERR-INVALID-INPUT (err u105))
(define-constant ERR-LICENSE-SUSPENDED (err u106))

;; Data Variables
(define-data-var next-provider-id uint u1)
(define-data-var contract-admin principal CONTRACT-OWNER)

;; Data Maps
(define-map providers
  { provider-id: uint }
  {
    principal: principal,
    first-name: (string-ascii 50),
    last-name: (string-ascii 50),
    email: (string-ascii 100),
    phone: (string-ascii 20),
    npi-number: (string-ascii 20),
    registration-date: uint,
    status: (string-ascii 20),
    specialization: (string-ascii 100)
  }
)

(define-map provider-licenses
  { provider-id: uint, state: (string-ascii 10) }
  {
    license-number: (string-ascii 50),
    issue-date: uint,
    expiry-date: uint,
    status: (string-ascii 20),
    license-type: (string-ascii 50)
  }
)

(define-map provider-certifications
  { provider-id: uint, certification-id: uint }
  {
    certification-name: (string-ascii 100),
    issuing-body: (string-ascii 100),
    issue-date: uint,
    expiry-date: uint,
    status: (string-ascii 20)
  }
)

(define-map provider-lookup
  { principal: principal }
  { provider-id: uint }
)

(define-map next-certification-id
  { provider-id: uint }
  { next-id: uint }
)

;; Read-only functions

(define-read-only (get-provider (provider-id uint))
  (map-get? providers { provider-id: provider-id })
)

(define-read-only (get-provider-by-principal (provider-principal principal))
  (match (map-get? provider-lookup { principal: provider-principal })
    lookup-data (get-provider (get provider-id lookup-data))
    none
  )
)

(define-read-only (get-provider-license (provider-id uint) (state (string-ascii 10)))
  (map-get? provider-licenses { provider-id: provider-id, state: state })
)

(define-read-only (get-provider-certification (provider-id uint) (certification-id uint))
  (map-get? provider-certifications { provider-id: provider-id, certification-id: certification-id })
)

(define-read-only (is-provider-licensed-in-state (provider-id uint) (state (string-ascii 10)))
  (match (get-provider-license provider-id state)
    license-data
      (and
        (is-eq (get status license-data) "active")
        (> (get expiry-date license-data) block-height)
      )
    false
  )
)

(define-read-only (get-provider-id-by-principal (provider-principal principal))
  (map-get? provider-lookup { principal: provider-principal })
)

(define-read-only (is-valid-provider (provider-id uint))
  (match (get-provider provider-id)
    provider-data (is-eq (get status provider-data) "active")
    false
  )
)

;; Public functions

(define-public (register-provider
  (first-name (string-ascii 50))
  (last-name (string-ascii 50))
  (email (string-ascii 100))
  (phone (string-ascii 20))
  (npi-number (string-ascii 20))
  (specialization (string-ascii 100))
)
  (let
    (
      (provider-id (var-get next-provider-id))
      (caller tx-sender)
    )
    ;; Check if provider is already registered
    (asserts! (is-none (map-get? provider-lookup { principal: caller })) ERR-ALREADY-REGISTERED)

    ;; Validate input
    (asserts! (> (len first-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len last-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len email) u0) ERR-INVALID-INPUT)
    (asserts! (> (len npi-number) u0) ERR-INVALID-INPUT)

    ;; Register provider
    (map-set providers
      { provider-id: provider-id }
      {
        principal: caller,
        first-name: first-name,
        last-name: last-name,
        email: email,
        phone: phone,
        npi-number: npi-number,
        registration-date: block-height,
        status: "pending",
        specialization: specialization
      }
    )

    ;; Create lookup mapping
    (map-set provider-lookup
      { principal: caller }
      { provider-id: provider-id }
    )

    ;; Initialize certification counter
    (map-set next-certification-id
      { provider-id: provider-id }
      { next-id: u1 }
    )

    ;; Increment provider ID counter
    (var-set next-provider-id (+ provider-id u1))

    (ok provider-id)
  )
)

(define-public (add-license
  (provider-id uint)
  (state (string-ascii 10))
  (license-number (string-ascii 50))
  (issue-date uint)
  (expiry-date uint)
  (license-type (string-ascii 50))
)
  (let
    (
      (caller tx-sender)
    )
    ;; Check authorization (provider or admin)
    (asserts!
      (or
        (is-eq caller (var-get contract-admin))
        (match (get-provider provider-id)
          provider-data (is-eq caller (get principal provider-data))
          false
        )
      )
      ERR-NOT-AUTHORIZED
    )

    ;; Validate input
    (asserts! (> (len state) u0) ERR-INVALID-INPUT)
    (asserts! (> (len license-number) u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date issue-date) ERR-INVALID-INPUT)

    ;; Add license
    (map-set provider-licenses
      { provider-id: provider-id, state: state }
      {
        license-number: license-number,
        issue-date: issue-date,
        expiry-date: expiry-date,
        status: "active",
        license-type: license-type
      }
    )

    (ok true)
  )
)

(define-public (add-certification
  (provider-id uint)
  (certification-name (string-ascii 100))
  (issuing-body (string-ascii 100))
  (issue-date uint)
  (expiry-date uint)
)
  (let
    (
      (caller tx-sender)
      (cert-id-data (default-to { next-id: u1 } (map-get? next-certification-id { provider-id: provider-id })))
      (certification-id (get next-id cert-id-data))
    )
    ;; Check authorization
    (asserts!
      (or
        (is-eq caller (var-get contract-admin))
        (match (get-provider provider-id)
          provider-data (is-eq caller (get principal provider-data))
          false
        )
      )
      ERR-NOT-AUTHORIZED
    )

    ;; Validate input
    (asserts! (> (len certification-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len issuing-body) u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date issue-date) ERR-INVALID-INPUT)

    ;; Add certification
    (map-set provider-certifications
      { provider-id: provider-id, certification-id: certification-id }
      {
        certification-name: certification-name,
        issuing-body: issuing-body,
        issue-date: issue-date,
        expiry-date: expiry-date,
        status: "active"
      }
    )

    ;; Update certification counter
    (map-set next-certification-id
      { provider-id: provider-id }
      { next-id: (+ certification-id u1) }
    )

    (ok certification-id)
  )
)

(define-public (approve-provider (provider-id uint))
  (let
    (
      (caller tx-sender)
    )
    ;; Only admin can approve
    (asserts! (is-eq caller (var-get contract-admin)) ERR-NOT-AUTHORIZED)

    ;; Check if provider exists
    (match (get-provider provider-id)
      provider-data
        (begin
          (map-set providers
            { provider-id: provider-id }
            (merge provider-data { status: "active" })
          )
          (ok true)
        )
      ERR-PROVIDER-NOT-FOUND
    )
  )
)

(define-public (suspend-provider (provider-id uint))
  (let
    (
      (caller tx-sender)
    )
    ;; Only admin can suspend
    (asserts! (is-eq caller (var-get contract-admin)) ERR-NOT-AUTHORIZED)

    ;; Check if provider exists
    (match (get-provider provider-id)
      provider-data
        (begin
          (map-set providers
            { provider-id: provider-id }
            (merge provider-data { status: "suspended" })
          )
          (ok true)
        )
      ERR-PROVIDER-NOT-FOUND
    )
  )
)

(define-public (update-license-status
  (provider-id uint)
  (state (string-ascii 10))
  (new-status (string-ascii 20))
)
  (let
    (
      (caller tx-sender)
    )
    ;; Only admin can update license status
    (asserts! (is-eq caller (var-get contract-admin)) ERR-NOT-AUTHORIZED)

    ;; Check if license exists
    (match (get-provider-license provider-id state)
      license-data
        (begin
          (map-set provider-licenses
            { provider-id: provider-id, state: state }
            (merge license-data { status: new-status })
          )
          (ok true)
        )
      ERR-INVALID-LICENSE
    )
  )
)

(define-public (renew-license
  (provider-id uint)
  (state (string-ascii 10))
  (new-expiry-date uint)
)
  (let
    (
      (caller tx-sender)
    )
    ;; Check authorization
    (asserts!
      (or
        (is-eq caller (var-get contract-admin))
        (match (get-provider provider-id)
          provider-data (is-eq caller (get principal provider-data))
          false
        )
      )
      ERR-NOT-AUTHORIZED
    )

    ;; Validate new expiry date
    (asserts! (> new-expiry-date block-height) ERR-INVALID-INPUT)

    ;; Check if license exists
    (match (get-provider-license provider-id state)
      license-data
        (begin
          (map-set provider-licenses
            { provider-id: provider-id, state: state }
            (merge license-data {
              expiry-date: new-expiry-date,
              status: "active"
            })
          )
          (ok true)
        )
      ERR-INVALID-LICENSE
    )
  )
)

;; Admin functions

(define-public (set-contract-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    (var-set contract-admin new-admin)
    (ok true)
  )
)

(define-read-only (get-contract-admin)
  (var-get contract-admin)
)
