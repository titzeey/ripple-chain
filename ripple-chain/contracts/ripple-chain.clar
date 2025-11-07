;; Ripple Chain DAO Governance Platform
;; A revolutionary cross-chain DAO governance platform with liquid democracy and reputation-weighted voting

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-proposal (err u104))
(define-constant err-proposal-expired (err u105))
(define-constant err-already-voted (err u106))
(define-constant err-insufficient-reputation (err u107))
(define-constant err-invalid-delegation (err u108))
(define-constant err-invalid-amount (err u109))
(define-constant err-proposal-not-passed (err u110))
(define-constant err-already-executed (err u111))

;; Proposal status constants
(define-constant proposal-status-active u1)
(define-constant proposal-status-passed u2)
(define-constant proposal-status-rejected u3)
(define-constant proposal-status-executed u4)

;; Minimum reputation required to create proposals
(define-constant min-proposal-reputation u100)

;; Voting period in blocks (approximately 7 days at 10 min/block)
(define-constant voting-period u1008)

;; Data Variables
(define-data-var proposal-nonce uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var total-reputation uint u0)

;; Data Maps

;; Member reputation scores
(define-map member-reputation
    principal
    {
        reputation-score: uint,
        total-proposals-created: uint,
        total-votes-cast: uint,
        active-delegations: uint,
        last-activity-block: uint
    }
)

;; Liquid delegation - members can delegate voting power to experts
(define-map delegations
    {delegator: principal, category: (string-ascii 50)}
    {
        delegate: principal,
        delegation-weight: uint,
        active: bool
    }
)

;; Proposals
(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-utf8 256),
        description: (string-utf8 1024),
        category: (string-ascii 50),
        treasury-amount: uint,
        recipient: (optional principal),
        start-block: uint,
        end-block: uint,
        status: uint,
        votes-for: uint,
        votes-against: uint,
        total-voting-power: uint,
        executed: bool
    }
)

;; Votes tracking
(define-map votes
    {proposal-id: uint, voter: principal}
    {
        vote-weight: uint,
        support: bool,
        block-height: uint
    }
)

;; Treasury allocations
(define-map treasury-allocations
    uint
    {
        amount: uint,
        recipient: principal,
        purpose: (string-utf8 256),
        executed: bool
    }
)

;; Member participation tracking
(define-map member-participation
    principal
    {
        proposals-voted: uint,
        proposals-created: uint,
        last-participation-block: uint,
        participation-streak: uint
    }
)

;; Read-only functions

(define-read-only (get-member-reputation (member principal))
    (default-to
        {
            reputation-score: u0,
            total-proposals-created: u0,
            total-votes-cast: u0,
            active-delegations: u0,
            last-activity-block: u0
        }
        (map-get? member-reputation member)
    )
)

(define-read-only (get-delegation (delegator principal) (category (string-ascii 50)))
    (map-get? delegations {delegator: delegator, category: category})
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-treasury-balance)
    (ok (var-get treasury-balance))
)

(define-read-only (get-proposal-nonce)
    (ok (var-get proposal-nonce))
)

(define-read-only (get-total-reputation)
    (ok (var-get total-reputation))
)

(define-read-only (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? votes {proposal-id: proposal-id, voter: voter}))
)

(define-read-only (get-member-participation (member principal))
    (default-to
        {
            proposals-voted: u0,
            proposals-created: u0,
            last-participation-block: u0,
            participation-streak: u0
        }
        (map-get? member-participation member)
    )
)

(define-read-only (calculate-voting-power (member principal))
    (let
        (
            (reputation-data (get-member-reputation member))
            (base-reputation (get reputation-score reputation-data))
        )
        (ok base-reputation)
    )
)

(define-read-only (is-proposal-active (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal-data
            (and
                (is-eq (get status proposal-data) proposal-status-active)
                (<= block-height (get end-block proposal-data))
            )
        false
    )
)

;; Public functions

;; Initialize member reputation
(define-public (initialize-member)
    (let
        (
            (existing-rep (map-get? member-reputation tx-sender))
        )
        (if (is-some existing-rep)
            err-already-exists
            (begin
                (map-set member-reputation
                    tx-sender
                    {
                        reputation-score: u10,
                        total-proposals-created: u0,
                        total-votes-cast: u0,
                        active-delegations: u0,
                        last-activity-block: block-height
                    }
                )
                (var-set total-reputation (+ (var-get total-reputation) u10))
                (ok true)
            )
        )
    )
)

;; Create a new proposal
(define-public (create-proposal
    (title (string-utf8 256))
    (description (string-utf8 1024))
    (category (string-ascii 50))
    (treasury-amount uint)
    (recipient (optional principal))
)
    (let
        (
            (member-rep (get-member-reputation tx-sender))
            (reputation-score (get reputation-score member-rep))
            (proposal-id (+ (var-get proposal-nonce) u1))
        )
        (asserts! (>= reputation-score min-proposal-reputation) err-insufficient-reputation)
        (asserts! (or (is-eq treasury-amount u0) (is-some recipient)) err-invalid-proposal)
        
        (map-set proposals
            proposal-id
            {
                proposer: tx-sender,
                title: title,
                description: description,
                category: category,
                treasury-amount: treasury-amount,
                recipient: recipient,
                start-block: block-height,
                end-block: (+ block-height voting-period),
                status: proposal-status-active,
                votes-for: u0,
                votes-against: u0,
                total-voting-power: u0,
                executed: false
            }
        )
        
        ;; Update member reputation
        (map-set member-reputation
            tx-sender
            (merge member-rep {
                total-proposals-created: (+ (get total-proposals-created member-rep) u1),
                reputation-score: (+ reputation-score u5),
                last-activity-block: block-height
            })
        )
        
        ;; Update participation tracking
        (update-participation-created tx-sender)
        
        (var-set proposal-nonce proposal-id)
        (ok proposal-id)
    )
)

;; Cast a vote on a proposal
(define-public (vote (proposal-id uint) (support bool))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals proposal-id) err-not-found))
            (member-rep (get-member-reputation tx-sender))
            (voting-power (get reputation-score member-rep))
        )
        (asserts! (is-proposal-active proposal-id) err-proposal-expired)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) err-already-voted)
        (asserts! (> voting-power u0) err-insufficient-reputation)
        
        ;; Record the vote
        (map-set votes
            {proposal-id: proposal-id, voter: tx-sender}
            {
                vote-weight: voting-power,
                support: support,
                block-height: block-height
            }
        )
        
        ;; Update proposal vote counts
        (map-set proposals
            proposal-id
            (merge proposal-data {
                votes-for: (if support (+ (get votes-for proposal-data) voting-power) (get votes-for proposal-data)),
                votes-against: (if support (get votes-against proposal-data) (+ (get votes-against proposal-data) voting-power)),
                total-voting-power: (+ (get total-voting-power proposal-data) voting-power)
            })
        )
        
        ;; Update member reputation for voting
        (map-set member-reputation
            tx-sender
            (merge member-rep {
                total-votes-cast: (+ (get total-votes-cast member-rep) u1),
                reputation-score: (+ voting-power u2),
                last-activity-block: block-height
            })
        )
        
        ;; Update participation tracking
        (update-participation-voted tx-sender)
        
        (ok true)
    )
)

;; Delegate voting power to another member
(define-public (delegate-voting-power
    (delegate principal)
    (category (string-ascii 50))
    (weight uint)
)
    (let
        (
            (delegator-rep (get-member-reputation tx-sender))
            (delegate-rep (get-member-reputation delegate))
        )
        (asserts! (not (is-eq tx-sender delegate)) err-invalid-delegation)
        (asserts! (> (get reputation-score delegate-rep) u0) err-not-found)
        (asserts! (<= weight (get reputation-score delegator-rep)) err-invalid-amount)
        
        (map-set delegations
            {delegator: tx-sender, category: category}
            {
                delegate: delegate,
                delegation-weight: weight,
                active: true
            }
        )
        
        ;; Update delegation counts
        (map-set member-reputation
            tx-sender
            (merge delegator-rep {
                active-delegations: (+ (get active-delegations delegator-rep) u1),
                last-activity-block: block-height
            })
        )
        
        (ok true)
    )
)

;; Revoke delegation
(define-public (revoke-delegation (category (string-ascii 50)))
    (let
        (
            (delegation-data (unwrap! (map-get? delegations {delegator: tx-sender, category: category}) err-not-found))
            (delegator-rep (get-member-reputation tx-sender))
        )
        (map-set delegations
            {delegator: tx-sender, category: category}
            (merge delegation-data {active: false})
        )
        
        (map-set member-reputation
            tx-sender
            (merge delegator-rep {
                active-delegations: (if (> (get active-delegations delegator-rep) u0)
                    (- (get active-delegations delegator-rep) u1)
                    u0
                )
            })
        )
        
        (ok true)
    )
)

;; Finalize proposal after voting period
(define-public (finalize-proposal (proposal-id uint))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals proposal-id) err-not-found))
            (votes-for (get votes-for proposal-data))
            (votes-against (get votes-against proposal-data))
            (new-status (if (> votes-for votes-against) proposal-status-passed proposal-status-rejected))
        )
        (asserts! (is-eq (get status proposal-data) proposal-status-active) err-invalid-proposal)
        (asserts! (> block-height (get end-block proposal-data)) err-proposal-expired)
        
        (map-set proposals
            proposal-id
            (merge proposal-data {status: new-status})
        )
        
        (ok new-status)
    )
)

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals proposal-id) err-not-found))
            (treasury-amount (get treasury-amount proposal-data))
            (recipient (get recipient proposal-data))
        )
        (asserts! (is-eq (get status proposal-data) proposal-status-passed) err-proposal-not-passed)
        (asserts! (not (get executed proposal-data)) err-already-executed)
        (asserts! (<= treasury-amount (var-get treasury-balance)) err-invalid-amount)
        
        ;; Update proposal as executed
        (map-set proposals
            proposal-id
            (merge proposal-data {
                status: proposal-status-executed,
                executed: true
            })
        )
        
        ;; Handle treasury transfer if applicable
        (if (and (> treasury-amount u0) (is-some recipient))
            (begin
                (var-set treasury-balance (- (var-get treasury-balance) treasury-amount))
                (map-set treasury-allocations
                    proposal-id
                    {
                        amount: treasury-amount,
                        recipient: (unwrap-panic recipient),
                        purpose: (get title proposal-data),
                        executed: true
                    }
                )
                (ok true)
            )
            (ok true)
        )
    )
)

;; Deposit funds to treasury
(define-public (deposit-to-treasury (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

;; Award reputation to a member (owner only)
(define-public (award-reputation (member principal) (amount uint))
    (let
        (
            (member-rep (get-member-reputation member))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        
        (map-set member-reputation
            member
            (merge member-rep {
                reputation-score: (+ (get reputation-score member-rep) amount),
                last-activity-block: block-height
            })
        )
        
        (var-set total-reputation (+ (var-get total-reputation) amount))
        (ok true)
    )
)

;; Private functions

(define-private (update-participation-created (member principal))
    (let
        (
            (participation (get-member-participation member))
        )
        (map-set member-participation
            member
            {
                proposals-voted: (get proposals-voted participation),
                proposals-created: (+ (get proposals-created participation) u1),
                last-participation-block: block-height,
                participation-streak: (calculate-streak (get last-participation-block participation))
            }
        )
    )
)

(define-private (update-participation-voted (member principal))
    (let
        (
            (participation (get-member-participation member))
        )
        (map-set member-participation
            member
            {
                proposals-voted: (+ (get proposals-voted participation) u1),
                proposals-created: (get proposals-created participation),
                last-participation-block: block-height,
                participation-streak: (calculate-streak (get last-participation-block participation))
            }
        )
    )
)

(define-private (calculate-streak (last-block uint))
    (if (< (- block-height last-block) u144) ;; Active within ~24 hours
        u1
        u0
    )
)
