;; Stack Subscribe - Subscription Management Smart Contract

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PLAN-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-SUBSCRIBED (err u102))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))
(define-constant ERR-SUBSCRIPTION-EXPIRED (err u105))
(define-constant ERR-INVALID-DURATION (err u106))
(define-constant ERR-INVALID-PRICE (err u107))
(define-constant ERR-INVALID-AMOUNT (err u108))
(define-constant ERR-INVALID-COST (err u109))
(define-constant ERR-INVALID-FREQUENCY (err u110))
(define-constant ERR-INVALID-SUBSCRIPTION-PLAN-ID (err u111))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map subscription-plans
  { plan-id: uint }
  {
    name: (string-ascii 50),
    price: uint,
    duration-blocks: uint,
    active: bool,
    created-at: uint,
    plan-id: uint
  })

(define-map subscriptions
  { plan-id: uint, subscriber: principal }
  {
    start-block: uint,
    end-block: uint,
    paid-amount: uint,
    active: bool,
    auto-renew: bool
  })

;; Variables
(define-data-var last-subscription-plan-id uint u0)
(define-data-var total-revenue uint u0)

;; Private helper functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER))

(define-private (assert-contract-owner)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok true)))

;; Validation functions
(define-private (check-uint (val uint))
  (> val u0))

(define-private (check-name (name (string-ascii 50)))
  (> (len name) u0))

(define-private (check-exists-plan (plan-id uint))
  (is-some (map-get? subscription-plans { plan-id: plan-id })))

;; Get subscription helper function
(define-private (get-subscription (plan-id uint) (subscriber principal))
  (map-get? subscriptions { plan-id: plan-id, subscriber: subscriber }))

(define-public (create-subscription-plan (cost uint) (frequency uint) (name (string-ascii 50)))
  (begin
    (try! (assert-contract-owner))
    (asserts! (check-uint cost) ERR-INVALID-COST)
    (asserts! (check-uint frequency) ERR-INVALID-FREQUENCY)
    (asserts! (check-name name) ERR-INVALID-PRICE)
    (let 
      ((new-id (+ (var-get last-subscription-plan-id) u1))
       (new-plan {
          plan-id: new-id,
          price: cost, 
          duration-blocks: frequency, 
          name: name, 
          created-at: burn-block-height, 
          active: true 
       }))
      (map-set subscription-plans
        { plan-id: new-id }
        new-plan)
      (var-set last-subscription-plan-id new-id)
      (print { 
        event: "create-subscription-plan", 
        plan-id: new-id, 
        price: cost, 
        duration-blocks: frequency, 
        name: name 
      })
      (ok new-id))))

(define-public (toggle-plan-status (plan-id uint))
  (begin
    (try! (assert-contract-owner))
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (asserts! (check-exists-plan plan-id) ERR-PLAN-NOT-FOUND)
    (let ((plan (unwrap! (map-get? subscription-plans {plan-id: plan-id}) ERR-PLAN-NOT-FOUND)))
      (map-set subscription-plans
        { plan-id: plan-id }
        (merge plan { active: (not (get active plan)) }))
      (print { 
        event: "plan-status-toggled", 
        plan-id: plan-id, 
        active: (not (get active plan)) 
      })
      (ok true))))

;; Subscribe to a plan
(define-public (subscribe (plan-id uint))
  (begin
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (asserts! (check-exists-plan plan-id) ERR-PLAN-NOT-FOUND)
    (let ((plan (unwrap! (map-get? subscription-plans { plan-id: plan-id }) ERR-PLAN-NOT-FOUND))
          (existing-sub (get-subscription plan-id tx-sender)))
      (begin
        (asserts! (get active plan) ERR-PLAN-NOT-FOUND)
        (asserts! (is-none existing-sub) ERR-ALREADY-SUBSCRIBED)
        
        ;; Create subscription
        (try! (stx-transfer? (get price plan) tx-sender (as-contract tx-sender)))
        (map-set subscriptions
          { plan-id: plan-id, subscriber: tx-sender }
          { 
            start-block: burn-block-height,
            end-block: (+ burn-block-height (get duration-blocks plan)),
            paid-amount: (get price plan),
            auto-renew: false,
            active: true
          })
        
        ;; Update revenue
        (var-set total-revenue (+ (var-get total-revenue) (get price plan)))
        (print { event: "subscription-created", plan-id: plan-id, subscriber: tx-sender })
        (ok true)))))

(define-public (renew-subscription (plan-id uint))
  (begin
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (asserts! (check-exists-plan plan-id) ERR-PLAN-NOT-FOUND)
    (let ((plan (unwrap! (map-get? subscription-plans { plan-id: plan-id }) ERR-PLAN-NOT-FOUND))
          (subscription (unwrap! (get-subscription plan-id tx-sender) ERR-SUBSCRIPTION-NOT-FOUND)))
      (begin
        (asserts! (get active plan) ERR-PLAN-NOT-FOUND)
        (asserts! (get active subscription) ERR-SUBSCRIPTION-NOT-FOUND)
        
        ;; Transfer payment to contract
        (try! (stx-transfer? (get price plan) tx-sender (as-contract tx-sender)))
        
        ;; Extend subscription
        (map-set subscriptions
          { plan-id: plan-id, subscriber: tx-sender }
          (merge subscription {
            end-block: (+ (get end-block subscription) (get duration-blocks plan)),
            paid-amount: (+ (get paid-amount subscription) (get price plan))
          }))
        
        ;; Update revenue
        (var-set total-revenue (+ (var-get total-revenue) (get price plan)))
        (print { 
          event: "subscription-renewed", 
          plan-id: plan-id, 
          subscriber: tx-sender 
        })
        (ok true)))))

(define-public (toggle-auto-renew (plan-id uint))
  (begin
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (asserts! (check-exists-plan plan-id) ERR-PLAN-NOT-FOUND)
    (let ((subscription (unwrap! (get-subscription plan-id tx-sender) ERR-SUBSCRIPTION-NOT-FOUND)))
      (begin
        (map-set subscriptions
          { plan-id: plan-id, subscriber: tx-sender }
          (merge subscription { 
            auto-renew: (not (get auto-renew subscription)) 
          }))
        (print { 
          event: "auto-renew-toggled", 
          plan-id: plan-id, 
          subscriber: tx-sender, 
          auto-renew: (not (get auto-renew subscription)) 
        })
        (ok true)))))

(define-public (cancel-subscription (plan-id uint))
  (begin
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (asserts! (check-exists-plan plan-id) ERR-PLAN-NOT-FOUND)
    (let ((subscription (unwrap! (get-subscription plan-id tx-sender) ERR-SUBSCRIPTION-NOT-FOUND)))
      (begin
        (map-set subscriptions
          { plan-id: plan-id, subscriber: tx-sender }
          (merge subscription { 
            active: false, 
            auto-renew: false 
          }))
        (print { 
          event: "subscription-cancelled", 
          plan-id: plan-id, 
          subscriber: tx-sender 
        })
        (ok true)))))

;; Read-only functions
(define-read-only (get-subscription-plan (plan-id uint))
  (begin
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (ok (unwrap! (map-get? subscription-plans { plan-id: plan-id })
                 ERR-PLAN-NOT-FOUND))))

(define-read-only (get-user-subscription (plan-id uint) (subscriber principal))
  (begin
    (asserts! (check-uint plan-id) ERR-INVALID-SUBSCRIPTION-PLAN-ID)
    (ok (unwrap! (get-subscription plan-id subscriber)
                 ERR-SUBSCRIPTION-NOT-FOUND))))

(define-read-only (has-active-subscription? (plan-id uint) (subscriber principal))
  (let ((sub (get-subscription plan-id subscriber)))
    (match sub
      subscription (and (get active subscription)
                       (> (get end-block subscription) burn-block-height))
      false)))

(define-read-only (get-total-revenue)
  (ok (var-get total-revenue)))

(define-read-only (get-last-plan-id)
  (ok (var-get last-subscription-plan-id)))

;; Emergency functions
(define-public (emergency-withdraw (amount uint))
  (begin
    (try! (assert-contract-owner))
    (asserts! (check-uint amount) ERR-INVALID-AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (print { event: "emergency-withdraw", amount: amount })
    (ok true)))


