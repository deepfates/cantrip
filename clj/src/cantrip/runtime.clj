(ns cantrip.runtime
  (:refer-clojure :exclude [cast send])
  (:require [cantrip.llm :as llm]
            [cantrip.domain :as domain]
            [cantrip.gates :as gates]
            [cantrip.loom :as loom]
            [cantrip.medium :as medium]
            [clojure.string :as str]))

(declare call-agent)
(declare call-agent-batch)

(defn- require-done-tool? [cantrip]
  (true? (get-in cantrip [:identity :require-done-tool])))

(defn- tool-choice [cantrip]
  (let [{:keys [tool-choice]} (medium/tool-view (:circle cantrip) (:identity cantrip))]
    tool-choice))

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
                     {:ok (llm/query (:llm cantrip) query-params)}
                     (catch clojure.lang.ExceptionInfo e
                       {:error e}))]
        (if-let [error (:error result)]
          (if (and (< attempt max-retries)
                   (retryable-error? error retryable-status-codes))
            (recur (inc attempt))
            (throw error))
          (:ok result))))))

(defn- ward-value
  [cantrip k]
  (some #(or (get % k) (get % (keyword (str/replace (name k) "-" "_"))))
        (get-in cantrip [:circle :wards])))

(defn- max-turns [cantrip]
  (or (ward-value cantrip :max-turns)
      1))

(defn- max-depth-ward [cantrip]
  (ward-value cantrip :max-depth))

(defn- llm-by-selector
  [named-llms selector]
  (let [selector-k (cond
                     (keyword? selector) selector
                     (string? selector) (keyword selector)
                     :else nil)
        by-name (when (string? selector)
                  (some (fn [[_ llm]]
                          (when (= selector (:name llm))
                            llm))
                        named-llms))]
    (or (get named-llms selector-k)
        by-name)))

(defn- normalize-request-gates
  [gates]
  (->> gates
       (map (fn [g]
              (if (string? g) (keyword g) g)))
       (cons :done)
       distinct
       vec))

(defn- child-llm-by-depth
  [named-llms parent-depth]
  (let [child-level (inc (long (or parent-depth 0)))]
    (or (get named-llms (keyword (str "child-llm-l" child-level)))
        (get named-llms (keyword (str "child_llm_l" child-level))))))

(def ^:private allowed-call-agent-request-keys
  #{:intent :cantrip :llm :gates :context :system-prompt})

(defn- validate-call-agent-request!
  [request]
  (when-not (map? request)
    (throw (ex-info "call-agent request must be a map"
                    {:request request})))
  (let [unknown (seq (remove allowed-call-agent-request-keys (keys request)))]
    (when unknown
      (throw (ex-info "call-agent request has unknown keys"
                      {:unknown-keys (vec unknown)}))))
  request)

(defn- max-child-calls-per-turn-ward
  [cantrip]
  (ward-value cantrip :max-child-calls-per-turn))

(defn- max-batch-size-ward
  [cantrip]
  (ward-value cantrip :max-batch-size))

(def ^:private default-child-system-prompt
  "You are a child entity. Pursue the intent and return the result. If you have a submit-answer or done function, call it with your answer.")

(defn- derive-child-cantrip
  [parent-cantrip request dependencies parent-depth]
  (let [named-llms (:named-llms dependencies)
        default-child-llm (:default-child-llm dependencies)
        requested-gates (:gates request)
        requested-llm (:llm request)
        depth-derived-llm (when (and (nil? requested-llm)
                                         (nil? default-child-llm))
                                (child-llm-by-depth named-llms parent-depth))
        chosen-llm (or (when requested-llm
                             (llm-by-selector named-llms requested-llm))
                           (when (and (nil? requested-llm)
                                      default-child-llm)
                             default-child-llm)
                           depth-derived-llm
                           (:llm parent-cantrip))
        ;; Strip delegation gates from child (prevents runaway recursion).
        ;; Child keeps done + parent's non-delegation gates.
        parent-gates (get-in parent-cantrip [:circle :gates])
        child-gates (when (and (seq parent-gates) (nil? requested-gates))
                      (vec (remove #{:call-entity :call-entity-batch
                                     "call_entity" "call_entity_batch"
                                     :call_entity :call_entity_batch}
                                   parent-gates)))
        ;; Cap child max-turns at 3 (prevents exponential blowup from error cascading)
        parent-max-turns (ward-value parent-cantrip :max-turns)
        child-max-turns (when parent-max-turns (min (long parent-max-turns) 3))]
    (cond-> (assoc parent-cantrip :llm chosen-llm)
      ;; Use requested gates if provided, otherwise strip delegation gates
      (seq requested-gates)
      (assoc-in [:circle :gates] (normalize-request-gates requested-gates))
      (and (seq child-gates) (nil? requested-gates))
      (assoc-in [:circle :gates] child-gates)
      ;; Cap child turns
      child-max-turns
      (assoc-in [:circle :wards] (conj (vec (get-in parent-cantrip [:circle :wards]))
                                        {:max-turns child-max-turns})))))

(defn- circle-tools [circle identity-config]
  (:tools (medium/tool-view circle identity-config)))

(defn- folding-config [cantrip]
  (get-in cantrip [:runtime :folding]))

(defn- max-turns-in-context [cantrip]
  (let [cfg (folding-config cantrip)]
    (or (:max-turns-in-context cfg)
        (:max_turns_in_context cfg))))

(defn- ephemeral-observations? [cantrip]
  (true? (get-in cantrip [:runtime :ephemeral-observations])))

(defn- code-medium-turn?
  "Returns true if this turn used the single-tool code medium pattern."
  [utterance]
  (let [tool-calls (:tool-calls utterance)]
    (and (= 1 (count tool-calls))
         (= "clojure" (name (or (:gate (first tool-calls)) ""))))))

(defn- format-observations-as-result
  "Combines multiple gate observations into a single result string for code medium."
  [obs compact-observation? turn]
  (if (empty? obs)
    "no output"
    (str/join "\n"
              (map-indexed (fn [idx record]
                             (let [content (if compact-observation?
                                            (str "[ephemeral-ref:" (:id turn) ":" idx "]")
                                            (str (:result record)))]
                               (if (:is-error record)
                                 (str "[" (:gate record) " ERROR] " content)
                                 (str "[" (:gate record) "] " content))))
                           obs))))

(defn- turn->messages [turn compact-observation?]
  (let [utterance (:utterance turn)
        obs (:observation turn)]
    (if (code-medium-turn? utterance)
      ;; Code medium: single tool_call → single tool response with combined observations
      (let [tool-call (first (:tool-calls utterance))
            assistant-msg {:role :assistant
                           :tool-calls [tool-call]}
            combined-result (format-observations-as-result obs compact-observation? turn)
            tool-msg {:role :tool
                      :name "clojure"
                      :tool-call-id (:id tool-call)
                      :content combined-result}]
        [assistant-msg tool-msg])
      ;; Conversation medium: one tool response per tool_call
      (let [needs-synth? (and (empty? (:tool-calls utterance)) (seq obs))
            obs-with-ids (if needs-synth?
                           (map-indexed (fn [idx record]
                                          (if (:tool-call-id record)
                                            record
                                            (assoc record :tool-call-id (str "synth_" (:id turn) "_" idx))))
                                        obs)
                           obs)
            synth-tool-calls (when needs-synth?
                               (mapv (fn [record]
                                       {:id (:tool-call-id record)
                                        :gate (:gate record)
                                        :args {}})
                                     obs-with-ids))
            effective-tool-calls (or (seq (:tool-calls utterance)) synth-tool-calls)
            assistant-msg (cond-> {:role :assistant}
                            (string? (:content utterance))
                            (assoc :content (:content utterance))
                            (seq effective-tool-calls)
                            (assoc :tool-calls (vec effective-tool-calls)))
            tool-msgs (map-indexed (fn [idx record]
                                     (cond-> {:role :tool
                                              :name (:gate record)
                                              :content (if compact-observation?
                                                         (str "[ephemeral-ref:" (:id turn) ":" idx "]")
                                                         (str (:result record)))}
                                       (:tool-call-id record)
                                       (assoc :tool-call-id (:tool-call-id record))))
                                   obs-with-ids)]
        (into [assistant-msg] tool-msgs)))))

(defn- build-messages [cantrip intent prior-turns current-cast-turns]
  (let [system-prompt (get-in cantrip [:identity :system-prompt])
        cap-text (medium/capability-text (:circle cantrip))
        base (cond-> []
               ;; Capability text first (medium physics + gate descriptions)
               (string? cap-text)
               (conj {:role :system :content cap-text})
               ;; Then developer's system prompt
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
              (let [compact? (and ephemeral? (pos? (count turns)))]
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
  ([entity-id cantrip intent prior-turns initial-loom initial-usage]
   (run-cast entity-id cantrip intent prior-turns initial-loom initial-usage {}))
  ([entity-id cantrip intent prior-turns initial-loom initial-usage {:keys [first-parent-id parent-entity]}]
   (let [turn-limit (max-turns cantrip)
         done-required? (require-done-tool? cantrip)
         {:keys [tools tool-choice capability-text]} (medium/tool-view (:circle cantrip) (:identity cantrip))
         selected-tool-choice tool-choice
         max-child-calls-per-turn (max-child-calls-per-turn-ward cantrip)
         max-batch-size (max-batch-size-ward cantrip)
         local-loom (atom initial-loom)
         local-history (atom (vec prior-turns))
         execution-parent (if parent-entity
                            (assoc parent-entity
                                   :loom local-loom
                                   :turn-history local-history
                                   :inline-intent intent
                                   :allow-inline-root-turn? true)
                            nil)]
     (loop [turn-index 0
            turns []
            loom-state initial-loom
            cumulative-usage initial-usage
            previous-tool-call-ids []]
       (if (>= turn-index turn-limit)
         (let [truncated-turns (if (seq turns)
                                 (assoc turns (dec (count turns))
                                        (assoc (last turns) :truncated true))
                                 turns)]
           {:entity-id entity-id
            :intent intent
            :status :truncated
            :result nil
            :turns truncated-turns
            :new-turns truncated-turns
            :cumulative-usage cumulative-usage
            :loom (if (seq turns)
                    (assoc loom-state :turns truncated-turns)
                    loom-state)})
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
               child-call-count (atom 0)
               _ (do
                   (reset! local-loom loom-state)
                   (reset! local-history (vec (concat prior-turns turns))))
               runtime-deps (let [raw-deps (or (get-in cantrip [:circle :dependencies]) {})
                                  base (assoc (select-keys raw-deps
                                                           [:filesystem
                                                            :player-fn
                                                            :xyz-fn
                                                            :block-fn
                                                            :set-block-fn
                                                            :allow-mutation?])
                                              :prior-turns turns)]
                              (if execution-parent
                                (assoc base
                                       :call-entity-fn
                                       (fn [request]
                                         (let [req (if (map? request)
                                                     request
                                                     {:intent (str request)})
                                               _ (validate-call-agent-request! req)
                                               parent-depth (long (or (:depth execution-parent) 0))
                                               _ (swap! child-call-count inc)
                                               _ (when (and (some? max-child-calls-per-turn)
                                                            (> @child-call-count (long max-child-calls-per-turn)))
                                                   (throw (ex-info "max child calls per turn exceeded"
                                                                   {:max-child-calls-per-turn (long max-child-calls-per-turn)})))
                                               child-cantrip (or (:cantrip req)
                                                                 (derive-child-cantrip cantrip req raw-deps parent-depth))
                                               response (call-agent execution-parent
                                                                    {:cantrip child-cantrip
                                                                     :intent (:intent req)})]
                                           (if (not= :terminated (:status response))
                                             (throw (ex-info (or (:error response) "child call failed")
                                                             {:response response}))
                                             (:result response))))
                                       :call-entity-batch-fn
                                       (fn [requests]
                                         (when-not (vector? requests)
                                           (throw (ex-info "call-agent-batch requires a vector of requests"
                                                           {:requests requests})))
                                         (when (and (some? max-batch-size)
                                                    (> (count requests) (long max-batch-size)))
                                           (throw (ex-info "batch size exceeds max-batch-size ward"
                                                           {:max-batch-size (long max-batch-size)
                                                            :count (count requests)})))
                                         (mapv (fn [request]
                                                 (let [req (if (map? request)
                                                             request
                                                             {:intent (str request)})
                                                       _ (validate-call-agent-request! req)
                                                       parent-depth (long (or (:depth execution-parent) 0))
                                                       _ (swap! child-call-count inc)
                                                       _ (when (and (some? max-child-calls-per-turn)
                                                                    (> @child-call-count (long max-child-calls-per-turn)))
                                                           (throw (ex-info "max child calls per turn exceeded"
                                                                           {:max-child-calls-per-turn (long max-child-calls-per-turn)})))
                                                       child-cantrip (or (:cantrip req)
                                                                         (derive-child-cantrip cantrip req raw-deps parent-depth))
                                                       response (call-agent execution-parent
                                                                            {:cantrip child-cantrip
                                                                             :intent (:intent req)})]
                                                   (if (not= :terminated (:status response))
                                                     (throw (ex-info (or (:error response) "child call failed")
                                                                     {:response response}))
                                                     (:result response))))
                                               requests)))
                                base))
               {:keys [observation terminated? result]} (medium/execute-utterance
                                                         (:circle cantrip)
                                                         utterance
                                                         runtime-deps)
               text-only? (and (empty? tool-calls)
                               (string? (:content utterance)))
               done-by-text? (and text-only? (not done-required?))
               turn-record {:sequence (inc turn-index)
                            :entity-id entity-id
                            :parent-id (when (and (zero? turn-index)
                                                  (some? first-parent-id))
                                         first-parent-id)
                            :utterance utterance
                            :observation observation
                            :metadata {:tokens_prompt (:prompt_tokens turn-usage)
                                       :tokens_completion (:completion_tokens turn-usage)
                                       :duration_ms (max 1 (long (/ (- query-end query-start) 1000000)))
                                       :timestamp (System/currentTimeMillis)}
                            :terminated (or terminated? done-by-text?)
                            :truncated false}
               active-loom @local-loom
               [next-loom stored-turn] (loom/append-turn active-loom turn-record)
               next-turns (conj turns stored-turn)]
           (reset! local-loom next-loom)
           (reset! local-history (vec (concat prior-turns next-turns)))
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
                          (mapv :id tool-calls)))))))))

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
        initial-loom (loom/new-loom (:identity cantrip))
        temp-entity {:entity-id entity-id
                     :cantrip cantrip
                     :loom (atom initial-loom)
                     :turn-history (atom [])
                     :depth 0}
        result (run-cast entity-id cantrip intent [] initial-loom {:prompt_tokens 0
                                                                   :completion_tokens 0}
                         {:parent-entity temp-entity})]
    (dissoc result
            :new-turns)))

(defn summon
  "Creates a persistent entity handle for multi-cast sessions."
  [cantrip]
  (domain/validate-cantrip! cantrip)
  (let [entity-id (str (random-uuid))
        medium-state (medium/snapshot-state (:circle cantrip)
                                            (get-in cantrip [:circle :dependencies]))]
    {:entity-id entity-id
     :cantrip cantrip
     :status :ready
     :loom (atom (loom/new-loom (:identity cantrip)))
     :medium-state (atom medium-state)
     :cumulative-usage (atom {:prompt_tokens 0
                              :completion_tokens 0})
     :turn-history (atom [])
     :depth 0}))

(defn send
  "Sends an intent to a summoned entity, preserving state across episodes."
  [entity intent]
  (domain/require-intent! intent)
  (let [cantrip (:cantrip entity)
        _ (domain/validate-cantrip! cantrip)
        prior-turns @(:turn-history entity)
        current-loom @(:loom entity)
        current-medium-state @(:medium-state entity)
        _ (medium/restore-state (:circle cantrip)
                                current-medium-state
                                (get-in cantrip [:circle :dependencies]))
        prior-usage @(:cumulative-usage entity)
        result (run-cast (:entity-id entity) cantrip intent prior-turns current-loom prior-usage
                         {:parent-entity entity})]
    (swap! (:turn-history entity) into (:new-turns result))
    (reset! (:loom entity) (:loom result))
    (reset! (:medium-state entity)
            (medium/snapshot-state (:circle cantrip)
                                   (get-in cantrip [:circle :dependencies])))
    (reset! (:cumulative-usage entity) (:cumulative-usage result))
    (dissoc result :new-turns)))

(defn entity-state
  "Returns current persistent state snapshot for a summoned entity."
  [entity]
  {:entity-id (:entity-id entity)
   :status (:status entity)
   :turn-count (count @(:turn-history entity))
   :medium-state @(:medium-state entity)
   :cumulative-usage @(:cumulative-usage entity)
   :loom @(:loom entity)})

(defn call-agent
  "Composes a child cast from a parent entity while preserving parent continuity."
  [parent-entity request]
  (validate-call-agent-request! request)
  (let [{:keys [cantrip intent context system-prompt]} request
        ;; If context is provided, prepend it to the intent so the child sees it.
        intent (if (some? context)
                 (let [ctx-str (if (string? context) context (pr-str context))]
                   (str "Context: " ctx-str "\n\nTask: " (or intent "")))
                 intent)
        parent-cantrip (:cantrip parent-entity)
        parent-depth (long (or (:depth parent-entity) 0))
        max-depth (max-depth-ward parent-cantrip)
        child-cantrip (or cantrip parent-cantrip)
        ;; Use request's system-prompt if provided; otherwise give children
        ;; a generic prompt so they don't inherit parent's delegation instructions.
        child-system-prompt (or system-prompt default-child-system-prompt)
        child-cantrip (assoc-in child-cantrip [:identity :system-prompt] child-system-prompt)]
    (cond
      (and (some? max-depth) (>= parent-depth (long max-depth)))
      {:status :error
       :error "max depth exceeded"}

      :else
      (try
        (domain/require-intent! intent)
        (domain/validate-cantrip! child-cantrip)
        (let [parent-loom @(:loom parent-entity)
              parent-history @(:turn-history parent-entity)
              parent-turn-id (:id (last parent-history))
              [initial-loom initial-parent-turn-id]
              (if (and (nil? parent-turn-id)
                       (:allow-inline-root-turn? parent-entity))
                (let [synthetic-parent-turn {:entity-id (:entity-id parent-entity)
                                             :utterance {:content (or (:inline-intent parent-entity) intent)}
                                             :observation [{:gate "call_entity"
                                                            :arguments "{}"
                                                            :result "inline composition bridge"}]
                                             :metadata {:tokens_prompt 0
                                                        :tokens_completion 0
                                                        :duration_ms 1
                                                        :timestamp (System/currentTimeMillis)}
                                             :terminated false
                                             :truncated false}
                      [loom-with-parent parent-turn] (loom/append-turn parent-loom synthetic-parent-turn)]
                  (reset! (:loom parent-entity) loom-with-parent)
                  (reset! (:turn-history parent-entity) (conj (vec parent-history) parent-turn))
                  [loom-with-parent (:id parent-turn)])
                [parent-loom parent-turn-id])
              child-id (str (random-uuid))
              child-entity {:entity-id child-id
                            :cantrip child-cantrip
                            :loom (atom initial-loom)
                            :turn-history (atom [])
                            :depth (inc parent-depth)}
              result (run-cast child-id
                               child-cantrip
                               intent
                               []
                               initial-loom
                               {:prompt_tokens 0 :completion_tokens 0}
                               {:first-parent-id initial-parent-turn-id
                                :parent-entity child-entity})]
          (reset! (:loom parent-entity) (:loom result))
          {:status (:status result)
           :result (:result result)
           :child-entity-id child-id
           :turns (:turns result)})
        (catch clojure.lang.ExceptionInfo e
          {:status :error
           :error (.getMessage e)
           :data (ex-data e)})))))

(defn call-agent-batch
  "Runs child compositions and returns results in input order."
  [parent-entity requests]
  (when-not (vector? requests)
    (throw (ex-info "call-agent-batch requires a vector of requests"
                    {:requests requests})))
  (let [max-batch-size (max-batch-size-ward (:cantrip parent-entity))]
    (when (and (some? max-batch-size)
               (> (count requests) (long max-batch-size)))
      (throw (ex-info "batch size exceeds max-batch-size ward"
                      {:max-batch-size (long max-batch-size)
                       :count (count requests)}))))
  (mapv #(call-agent parent-entity %) requests))
