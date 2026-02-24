(ns cantrip.runtime
  (:refer-clojure :exclude [cast])
  (:require [cantrip.crystal :as crystal]
            [cantrip.domain :as domain]
            [cantrip.gates :as gates]
            [cantrip.loom :as loom]
            [cantrip.medium :as medium]))

(defn- max-turns [cantrip]
  (or (some :max-turns (get-in cantrip [:circle :wards]))
      1))

(defn- require-done-tool? [cantrip]
  (true? (get-in cantrip [:call :require-done-tool])))

(defn- tool-choice [cantrip]
  (or (get-in cantrip [:call :tool-choice])
      :auto))

(defn- retry-config [cantrip]
  (let [cfg (:retry cantrip)]
    {:max-retries (long (or (:max-retries cfg) (:max_retries cfg) 0))
     :retryable-status-codes (set (or (:retryable-status-codes cfg)
                                      (:retryable_status_codes cfg)
                                      []))}))

(defn- retryable-error? [error retryable-status-codes]
  (let [status (:status (ex-data error))]
    (and (integer? status) (contains? retryable-status-codes status))))

(defn- query-with-retry
  [cantrip query-params]
  (let [{:keys [max-retries retryable-status-codes]} (retry-config cantrip)]
    (loop [attempt 0]
      (let [result (try
                     {:ok (crystal/query (:crystal cantrip) query-params)}
                     (catch clojure.lang.ExceptionInfo e
                       {:error e}))]
        (if-let [error (:error result)]
          (if (and (< attempt max-retries)
                   (retryable-error? error retryable-status-codes))
            (recur (inc attempt))
            (throw error))
          (:ok result))))))

(defn- circle-tools [circle]
  (gates/gate-tools (:gates circle)))

(defn- folding-config [cantrip]
  (get-in cantrip [:runtime :folding]))

(defn- max-turns-in-context [cantrip]
  (let [cfg (folding-config cantrip)]
    (or (:max-turns-in-context cfg)
        (:max_turns_in_context cfg))))

(defn- ephemeral-observations? [cantrip]
  (true? (get-in cantrip [:runtime :ephemeral-observations])))

(defn- turn->messages [turn compact-observation?]
  (let [utterance (:utterance turn)
        assistant-msg (cond-> {:role :assistant}
                        (string? (:content utterance))
                        (assoc :content (:content utterance))
                        (seq (:tool-calls utterance))
                        (assoc :tool-calls (vec (:tool-calls utterance))))
        tool-msgs (map-indexed (fn [idx record]
                                 {:role :tool
                                  :name (:gate record)
                                  :content (if compact-observation?
                                             (str "[ephemeral-ref:" (:id turn) ":" idx "]")
                                             (str (:result record)))})
                               (:observation turn))]
    (into [assistant-msg] tool-msgs)))

(defn- build-messages [cantrip intent prior-turns current-cast-turns]
  (let [system-prompt (get-in cantrip [:call :system-prompt])
        base (cond-> []
               (string? system-prompt)
               (conj {:role :system :content system-prompt})
               :always
               (conj {:role :user :content intent}))
        all-turns (vec (concat prior-turns current-cast-turns))
        keep-limit (max-turns-in-context cantrip)
        [folded-count turns] (if (and (integer? keep-limit)
                                      (pos? keep-limit)
                                      (> (count all-turns) keep-limit))
                               [(- (count all-turns) keep-limit)
                                (subvec all-turns (- (count all-turns) keep-limit))]
                               [0 all-turns])
        with-folding (if (pos? folded-count)
                       (conj base {:role :system
                                   :content (str "Folded " folded-count " prior turns into summary context.")})
                       base)
        ephemeral? (ephemeral-observations? cantrip)]
    (reduce (fn [acc [idx turn]]
              (let [compact? (and ephemeral? (< idx (dec (count turns))))]
                (into acc (turn->messages turn compact?))))
            with-folding
            (map-indexed vector turns))))

(defn- normalize-usage [usage]
  {:prompt_tokens (long (or (:prompt_tokens usage) (:prompt-tokens usage) 0))
   :completion_tokens (long (or (:completion_tokens usage) (:completion-tokens usage) 0))})

(defn- add-usage [lhs rhs]
  {:prompt_tokens (+ (long (or (:prompt_tokens lhs) 0))
                     (long (or (:prompt_tokens rhs) 0)))
   :completion_tokens (+ (long (or (:completion_tokens lhs) 0))
                         (long (or (:completion_tokens rhs) 0)))})

(defn- run-cast
  [entity-id cantrip intent prior-turns initial-loom initial-usage]
  (let [turn-limit (max-turns cantrip)
        done-required? (require-done-tool? cantrip)
        selected-tool-choice (tool-choice cantrip)
        tools (circle-tools (:circle cantrip))]
    (loop [turn-index 0
           turns []
           loom-state initial-loom
           cumulative-usage initial-usage
           previous-tool-call-ids []]
      (if (>= turn-index turn-limit)
        {:entity-id entity-id
         :intent intent
         :status :truncated
         :result nil
         :turns turns
         :new-turns turns
         :cumulative-usage cumulative-usage
         :loom loom-state}
        (let [messages (build-messages cantrip intent prior-turns turns)
              query-start (System/nanoTime)
              utterance (query-with-retry cantrip
                                          {:turn-index turn-index
                                           :messages messages
                                           :tools tools
                                           :tool-choice selected-tool-choice
                                           :previous-tool-call-ids previous-tool-call-ids})
              query-end (System/nanoTime)
              turn-usage (normalize-usage (:usage utterance))
              next-cumulative-usage (add-usage cumulative-usage turn-usage)
              tool-calls (vec (:tool-calls utterance))
              {:keys [observation terminated? result]} (medium/execute-utterance
                                                        (:circle cantrip)
                                                        utterance
                                                        (get-in cantrip [:circle :dependencies]))
              text-only? (and (empty? tool-calls)
                              (string? (:content utterance)))
              done-by-text? (and text-only? (not done-required?))
              turn-record {:sequence (inc turn-index)
                           :utterance utterance
                           :observation observation
                           :metadata {:tokens_prompt (:prompt_tokens turn-usage)
                                      :tokens_completion (:completion_tokens turn-usage)
                                      :duration_ms (max 0 (long (/ (- query-end query-start) 1000000)))
                                      :timestamp (System/currentTimeMillis)}
                           :terminated (or terminated? done-by-text?)
                           :truncated false}
              [next-loom _] (loom/append-turn loom-state turn-record)
              next-turns (conj turns turn-record)]
          (cond
            terminated? {:entity-id entity-id
                         :intent intent
                         :status :terminated
                         :result result
                         :turns next-turns
                         :new-turns next-turns
                         :cumulative-usage next-cumulative-usage
                         :loom next-loom}

            done-by-text? {:entity-id entity-id
                           :intent intent
                           :status :terminated
                           :result (:content utterance)
                           :turns next-turns
                           :new-turns next-turns
                           :cumulative-usage next-cumulative-usage
                           :loom next-loom}

            :else (recur (inc turn-index)
                         next-turns
                         next-loom
                         next-cumulative-usage
                         (mapv :id tool-calls))))))))

(defn new-cantrip
  "Constructs and validates a cantrip value."
  [cantrip]
  (domain/validate-cantrip! cantrip))

(defn cast
  "Runs one cast (one intent episode) and returns a result map."
  [cantrip intent]
  (domain/validate-cantrip! cantrip)
  (domain/require-intent! intent)
  (let [entity-id (str (random-uuid))
        initial-loom (loom/new-loom (:call cantrip))]
    (dissoc (run-cast entity-id cantrip intent [] initial-loom {:prompt_tokens 0
                                                                :completion_tokens 0})
            :new-turns)))

(defn invoke
  "Creates a persistent entity handle for multi-cast sessions."
  [cantrip]
  (domain/validate-cantrip! cantrip)
  (let [entity-id (str (random-uuid))]
    {:entity-id entity-id
     :cantrip cantrip
     :status :ready
     :loom (atom (loom/new-loom (:call cantrip)))
     :cumulative-usage (atom {:prompt_tokens 0
                              :completion_tokens 0})
     :turn-history (atom [])}))

(defn cast-intent
  "Runs one intent against an invoked entity, preserving state across casts."
  [entity intent]
  (domain/require-intent! intent)
  (let [cantrip (:cantrip entity)
        _ (domain/validate-cantrip! cantrip)
        prior-turns @(:turn-history entity)
        current-loom @(:loom entity)
        prior-usage @(:cumulative-usage entity)
        result (run-cast (:entity-id entity) cantrip intent prior-turns current-loom prior-usage)]
    (swap! (:turn-history entity) into (:new-turns result))
    (reset! (:loom entity) (:loom result))
    (reset! (:cumulative-usage entity) (:cumulative-usage result))
    (dissoc result :new-turns)))

(defn entity-state
  "Returns current persistent state snapshot for an invoked entity."
  [entity]
  {:entity-id (:entity-id entity)
   :status (:status entity)
   :turn-count (count @(:turn-history entity))
   :cumulative-usage @(:cumulative-usage entity)
   :loom @(:loom entity)})
