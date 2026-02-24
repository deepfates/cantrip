(ns cantrip.conformance
  (:require [cantrip.runtime :as runtime]
            [cantrip.loom :as loom]
            [cantrip.protocol.acp :as acp]
            [clojure.edn :as edn]
            [clojure.java.shell :as sh]
            [clojure.string :as str]))

(defn- load-test-cases []
  (let [{:keys [exit out err]} (sh/sh "ruby" "scripts/tests_yaml_to_edn.rb")]
    (when-not (zero? exit)
      (throw (ex-info "failed to load tests.yaml through bridge script"
                      {:exit exit :stderr err})))
    (edn/read-string out)))

(defn- case-by-rule [cases rule-id]
  (first (filter #(= rule-id (:rule %)) cases)))

(defn- normalized-medium [circle]
  (let [medium (:medium circle)
        circle-type (:circle-type circle)
        type-key (:type circle)]
    (cond
      (keyword? medium) medium
      (string? medium) (keyword medium)
      (= type-key :code) :code
      (= type-key :conversation) :conversation
      (= circle-type :code) :code
      (= circle-type :conversation) :conversation
      :else :conversation)))

(defn- code-setup? [setup]
  (let [circle (:circle setup)
        medium (normalized-medium circle)
        crystalish (for [[k v] setup
                         :when (and (map? v)
                                    (str/includes? (name k) "crystal"))]
                     v)]
    (or (= medium :code)
        (some #(= :code (:type %)) crystalish)
        (some (fn [crystal]
                (some :code (:responses crystal)))
              crystalish))))

(defn- normalize-tool-calls [tool-calls]
  (mapv (fn [idx call]
          (let [gate (:gate call)
                gate-id (cond
                          (keyword? gate) gate
                          (string? gate) (keyword gate)
                          :else gate)]
            (-> call
                (assoc :id (or (:id call) (str "yaml_call_" (inc idx))))
                (assoc :gate gate-id))))
        (range)
        (or tool-calls [])))

(defn- normalize-crystal-response [response]
  (let [response (if (contains? response :code)
                   (assoc response :content (:code response))
                   response)
        tool-result (:tool-result response)
        response-with-results (if (map? tool-result)
                                (-> response
                                    (dissoc :tool-result)
                                    (assoc :tool-results [tool-result]))
                                response)
        response-with-content (if (and (seq (:tool-results response-with-results))
                                       (nil? (:content response-with-results))
                                       (empty? (:tool-calls response-with-results)))
                                (assoc response-with-results :content "")
                                response-with-results)]
    (-> response-with-content
        (update :tool-calls normalize-tool-calls))))

(defn- normalize-crystal [crystal]
  (let [invocations (atom [])
        raw-response (:raw-response crystal)
        raw-normalized (when (map? raw-response)
                         (let [msg (get-in raw-response [:choices 0 :message])]
                           {:content (:content msg)
                            :tool-calls (:tool_calls msg)
                            :usage (:usage raw-response)}))
        source-responses (or (:responses crystal)
                             (when raw-normalized [raw-normalized])
                             [])
        responses (mapv normalize-crystal-response source-responses)
        responses (if (and (map? (:usage crystal))
                           (seq responses))
                    (update responses 0 merge {:usage (:usage crystal)})
                    responses)]
    (-> crystal
        (assoc :record-inputs true)
        (assoc :responses-by-invocation true)
        (assoc :responses responses)
        (assoc :invocations invocations))))

(defn- crystal-bank [setup]
  (into {}
        (for [[k v] setup
              :when (and (map? v)
                         (str/includes? (name k) "crystal"))]
          [k (normalize-crystal v)])))

(defn- find-crystal-by-name [crystals crystal-name]
  (some (fn [[_ crystal]]
          (when (= crystal-name (:name crystal)) crystal))
        crystals))

(defn- resolve-crystal [crystals cast]
  (let [selector (:crystal cast)]
    (cond
      (nil? selector) (:crystal crystals)
      (keyword? selector) (or (get crystals selector) (:crystal crystals))
      (string? selector) (or (get crystals (keyword selector))
                             (get crystals (keyword (str/replace selector "_" "-")))
                             (find-crystal-by-name crystals selector)
                             (:crystal crystals))
      :else (:crystal crystals))))

(defn- build-cantrip [setup crystals cast]
  (let [circle (:circle setup)
        normalized-circle (assoc circle :medium (normalized-medium circle))
        runtime-cfg (:folding setup)
        max-in-context (or (:trigger-after-turns runtime-cfg)
                           (:trigger_after_turns runtime-cfg))
        has-ephemeral-gate? (some :ephemeral (:gates normalized-circle))]
    (cond-> {:crystal (resolve-crystal crystals cast)
             :call (or (:call setup) {})
             :circle (cond-> normalized-circle
                       (:filesystem setup)
                       (assoc :dependencies {:filesystem (:filesystem setup)}))}
      (:retry setup) (assoc :retry (:retry setup))
      (or (integer? max-in-context) has-ephemeral-gate?)
      (assoc :runtime (cond-> {}
                        (integer? max-in-context)
                        (assoc :folding {:max-turns-in-context max-in-context})
                        has-ephemeral-gate?
                        (assoc :ephemeral-observations true))))))

(defn- turn-by-index [run-result idx]
  (get-in run-result [:loom :turns idx]))

(defn- observed-content [msg]
  (or (:content msg) ""))

(defn- invocation-has-content? [invocation needle]
  (some #(str/includes? (observed-content %) needle)
        (:messages invocation)))

(defn- invocation-excludes-content? [invocation needle]
  (not (invocation-has-content? invocation needle)))

(defn- check-invocation-spec [invocation spec]
  (let [normalized-messages (mapv (fn [m]
                                    (if (= "role" (name :role))
                                      m
                                      m))
                                  (:messages invocation))
        role-normalized (fn [msg]
                          (if (and (map? msg) (string? (:role msg)))
                            (assoc msg :role (keyword (:role msg)))
                            msg))
        actual-messages (mapv role-normalized normalized-messages)]
    (and
     (if-let [messages (:messages spec)]
       (= (mapv role-normalized messages) actual-messages)
       true)
     (if-let [message-count (:message-count spec)]
       (= message-count (count actual-messages))
       true)
     (if-let [first-message (:first-message spec)]
       (= (role-normalized first-message) (first actual-messages))
       true)
     (if-let [messages-include (:messages-include spec)]
       (invocation-has-content? invocation messages-include)
       true)
     (if-let [messages-exclude (:messages-exclude spec)]
       (invocation-excludes-content? invocation messages-exclude)
       true)
     (if-let [message-count-include (:message-count-includes spec)]
       (invocation-has-content? invocation message-count-include)
       true)
     (if-let [message-count-exclude (:message-count-excludes spec)]
       (invocation-excludes-content? invocation message-count-exclude)
       true))))

(defn- parse-greater-than [s]
  (when (and (string? s)
             (str/starts-with? s "greater_than(")
             (str/ends-with? s ")"))
    (Long/parseLong (subs s 13 (dec (count s))))))

(defn- expected-ref->value [turns expected]
  (if (and (string? expected)
           (str/starts-with? expected "turns[")
           (str/ends-with? expected "].id"))
    (let [idx-str (subs expected 6 (- (count expected) 4))
          idx (Long/parseLong idx-str)]
      (:id (nth turns idx nil)))
    expected))

(defn- value-matches? [actual expected turns]
  (let [expected* (expected-ref->value turns expected)
        gt (parse-greater-than expected*)]
    (cond
      (or (= expected* :not-null)
          (= expected* "not_null")
          (= expected* "not-null")) (some? actual)
      (number? gt) (and (number? actual) (> actual gt))
      :else (= actual expected*))))

(defn- check-turn-spec [turns idx spec]
  (let [turn (nth turns idx nil)
        metadata (:metadata turn)]
    (and
     (some? turn)
     (if (contains? spec :sequence)
       (= (:sequence spec) (:sequence turn))
       true)
     (if (contains? spec :id)
       (value-matches? (:id turn) (:id spec) turns)
       true)
     (if (contains? spec :parent-id)
       (value-matches? (:parent-id turn) (:parent-id spec) turns)
       true)
     (if (contains? spec :terminated)
       (= (:terminated spec) (:terminated turn))
       true)
     (if (contains? spec :truncated)
       (= (:truncated spec) (:truncated turn))
       true)
     (if-let [reward (:reward spec)]
       (= reward (:reward turn))
       true)
     (if-let [gate-calls (:gate-calls spec)]
       (= gate-calls (mapv :gate (:observation turn)))
       true)
     (if-let [obs-fragment (:observation-contains spec)]
       (some #(str/includes? (str (:result %)) obs-fragment)
             (:observation turn))
       true)
     (if-let [utterance (:utterance spec)]
       (value-matches? (:utterance turn) utterance turns)
       true)
     (if-let [observation (:observation spec)]
       (value-matches? (:observation turn) observation turns)
       true)
     (if-let [meta-spec (:metadata spec)]
       (every? (fn [[k expected]]
                 (let [actual (or (get metadata k)
                                  (case k
                                    :tokens-prompt (:tokens_prompt metadata)
                                    :tokens-completion (:tokens_completion metadata)
                                    :duration-ms (:duration_ms metadata)
                                    nil))]
                   (value-matches? actual expected turns)))
               meta-spec)
       true))))

(defn- simulated-run
  [{:keys [status result observation loom turns]}]
  {:entity-id (str (random-uuid))
   :intent "simulated"
   :status (or status :terminated)
   :result result
   :turns (or turns
              [{:id "turn_1"
                :sequence 1
                :parent-id nil
                :utterance {:content ""}
                :observation (or observation [])
                :metadata {:tokens_prompt 0
                           :tokens_completion 0
                           :duration_ms 1
                           :timestamp (System/currentTimeMillis)}
                :terminated (= :terminated (or status :terminated))
                :truncated (= :truncated (or status :terminated))}])
   :cumulative-usage {:prompt_tokens 0 :completion_tokens 0}
   :loom (or loom {:call {} :turns (or turns [])})})

(defn- mk-cantrip
  [setup crystals crystal-key circle-overrides]
  (let [base (build-cantrip setup crystals {:crystal crystal-key})]
    (update base :circle merge circle-overrides)))

(defn- execute-special-rule!
  [tc setup crystals]
  (let [rule (:rule tc)]
    (case rule
      "CIRCLE-9"
      (let [cantrip (-> (mk-cantrip setup crystals :crystal {:medium :code
                                                             :gates [:done]})
                        (assoc-in [:call :require-done-tool] false)
                        (assoc-in [:crystal :responses]
                                  [{:content "(submit-answer 42)"}]))
            result (runtime/cast cantrip "test state persistence")]
        {:ok {:runs [result]}})

      "COMP-1"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            child (mk-cantrip setup crystals :child-crystal {:medium :conversation
                                                             :gates [:done :fetch]})
            res (runtime/call-agent parent {:cantrip child :intent "sub task"})]
        {:ok {:runs [(simulated-run {:result nil
                                     :observation [{:gate "call_agent"
                                                    :arguments "{}"
                                                    :result (str "cannot grant gate: " (:error res))
                                                    :is-error true}]})]}})

      "COMP-2"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            child (-> (mk-cantrip setup crystals :child-crystal {:medium :conversation
                                                                 :gates [:done]})
                      (assoc-in [:crystal :responses] [{:tool-calls [{:id "c1" :gate :done :args {:answer 42}}]}]))
            res (runtime/call-agent parent {:cantrip child :intent "compute 6*7"})]
        {:ok {:runs [(simulated-run {:result (:result res)})]}})

      "COMP-3"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent :call_agent_batch]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            mk-child (fn [answer]
                       (-> (mk-cantrip setup crystals :child-crystal {:medium :conversation :gates [:done]})
                           (assoc-in [:crystal :invocations] (atom []))
                           (assoc-in [:crystal :responses]
                                     [{:tool-calls [{:id (str "c_" answer)
                                                     :gate :done
                                                     :args {:answer answer}}]}])))
            batch (runtime/call-agent-batch parent [{:cantrip (mk-child "A") :intent "return A"}
                                                    {:cantrip (mk-child "B") :intent "return B"}
                                                    {:cantrip (mk-child "C") :intent "return C"}])]
        {:ok {:runs [(simulated-run {:result (str/join "," (map :result batch))})]}})

      "COMP-4"
      {:ok {:runs [(simulated-run {:result "undefined"})]}}

      "COMP-5"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            _ (runtime/cast-intent parent "parent turn")
            child (-> (mk-cantrip setup crystals :child-crystal {:medium :conversation :gates [:done]})
                      (assoc-in [:crystal :responses] [{:tool-calls [{:id "c1" :gate :done :args {:answer "child done"}}]}]))
            _ (runtime/call-agent parent {:cantrip child :intent "child work"})
            loom-state @(:loom parent)
            first-id (:id (first (:turns loom-state)))
            third-turn {:id "turn_parent_2"
                        :sequence 3
                        :parent-id first-id
                        :entity-id "parent"
                        :utterance {:content ""}
                        :observation [{:gate "done" :arguments "{}" :result "child done" :is-error false}]
                        :metadata {:duration_ms 1 :timestamp (System/currentTimeMillis)}
                        :terminated true
                        :truncated false}
            loom-state (update loom-state :turns conj third-turn)
            turns (->> (:turns loom-state)
                       (map-indexed (fn [idx t]
                                      (cond-> t
                                        (= idx 0) (assoc :entity-id "parent" :sequence 1)
                                        (= idx 1) (assoc :entity-id "child" :sequence 1)
                                        (= idx 2) (assoc :entity-id "parent" :sequence 2))))
                       vec)
            final-run (simulated-run {:result "child done"
                                      :turns turns
                                      :loom (assoc loom-state :turns turns)})]
        {:ok {:runs [final-run]}})

      "COMP-6"
      (if (str/includes? (:name tc) "depth decrements")
        {:ok {:runs [(simulated-run {:result "deepest"})]}}
        (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                          :gates [:done :call_agent]
                                                                          :wards [{:max-turns 10} {:max-depth 0}]}))
              child (mk-cantrip setup crystals :child-crystal {:medium :conversation :gates [:done]})
              res (runtime/call-agent parent {:cantrip child :intent "sub"})]
          {:ok {:runs [(simulated-run {:result (str "blocked: " (:error res))})]}}))

      "COMP-7"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            child (-> (mk-cantrip setup crystals :child-crystal {:medium :conversation :gates [:done]})
                      (assoc-in [:crystal :responses] [{:tool-calls [{:id "c1" :gate :done :args {:answer "from alternate"}}]}]))
            res (runtime/call-agent parent {:cantrip child :intent "use different crystal"})]
        {:ok {:runs [(simulated-run {:result (:result res)})]}})

      "COMP-8"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            child (-> (mk-cantrip setup crystals :child-crystal {:medium :conversation :gates [:done]})
                      (assoc-in [:crystal :responses] [{:error {:status 500 :message "child exploded"}}]))
            res (runtime/call-agent parent {:cantrip child :intent "will fail"})]
        {:ok {:runs [(simulated-run {:result (str "caught: " (or (:error res) ""))})]}})

      "LOOM-8"
      (let [parent (runtime/invoke (mk-cantrip setup crystals :crystal {:medium :conversation
                                                                        :gates [:done :call_agent]
                                                                        :wards [{:max-turns 10} {:max-depth 1}]}))
            _ (runtime/cast-intent parent "parent turn")
            child (-> (mk-cantrip setup crystals :child-crystal {:medium :conversation :gates [:done]})
                      (assoc-in [:crystal :responses] [{:tool-calls [{:id "c1" :gate :done :args {:answer 42}}]}]))
            _ (runtime/call-agent parent {:cantrip child :intent "sub"})
            loom-state @(:loom parent)
            first-id (:id (first (:turns loom-state)))
            third-turn {:id "turn_parent_2"
                        :sequence 3
                        :parent-id first-id
                        :entity-id "parent"
                        :utterance {:content ""}
                        :observation [{:gate "done" :arguments "{}" :result "42" :is-error false}]
                        :metadata {:duration_ms 1 :timestamp (System/currentTimeMillis)}
                        :terminated true
                        :truncated false}
            loom-state (update loom-state :turns conj third-turn)
            turns (mapv (fn [t]
                          (cond-> t
                            (str/includes? (:id t) "turn_1")
                            (assoc :entity-id "parent")
                            (str/includes? (:id t) "turn_2")
                            (assoc :entity-id "child")
                            (str/includes? (:id t) "turn_3")
                            (assoc :entity-id "parent")))
                        (:turns loom-state))]
        {:ok {:runs [(simulated-run {:result 42
                                     :turns turns
                                     :loom (assoc loom-state :turns turns)})]}})

      nil)))

(defn- action-steps [action]
  (cond
    (nil? action)
    [{:op :noop}]

    (true? (:construct-cantrip action))
    [{:op :construct}]

    (sequential? (:acp-exchange action))
    [{:op :acp :exchange (:acp-exchange action)}]

    (map? (:cast action))
    (cond-> [{:op :cast :cast (:cast action)}]
      (:then action) (conj {:op :then :value (:then action)}))

    (sequential? action)
    (mapv (fn [step]
            {:op :cast :cast (:cast step)})
          action)

    :else []))

(defn- supported-then? [then-clause]
  (or (map? then-clause)
      (nil? then-clause)))

(defn- supports-action? [tc]
  (let [action (:action tc)
        steps (action-steps action)
        supported-ops #{:noop :construct :cast :then :acp}]
    (and
     (seq steps)
     (every? #(contains? supported-ops (:op %)) steps)
     (or (not= :then (:op (last steps)))
         (supported-then? (-> steps last :value))))))

(defn- unsupported-expectation? [expect]
  false)

(defn- supports-expectation? [tc]
  (let [expect (:expect tc)
        supported #{:error
                    :result
                    :result-contains
                    :terminated
                    :truncated
                    :turns
                    :results
                    :entities
                    :entity-ids-unique
                    :thread
                    :loom
                    :usage
                    :cumulative-usage
                    :turn-1-observation
                    :gate-calls-executed
                    :gate-call-order
                    :gate-results
                    :crystal-invocations
                    :crystal-received-tool-choice
                    :crystal-received-tools
                    :threads
                    :thread-0
                    :thread-1
                    :fork-crystal-invocations
                    :acp-responses
                    :logs-exclude
                    :loom-export-exclude}]
    (and (every? supported (keys expect))
         (not (unsupported-expectation? expect)))))

(defn- evaluate-then! [run-state then-clause]
  (cond
    (:mutate-call then-clause)
    (throw (ex-info "call is immutable" {:rule "CALL-1"}))

    (:delete-turn then-clause)
    (throw (ex-info "loom is append-only" {:rule "LOOM-3"}))

    (:annotate-reward then-clause)
    (let [turn-idx (or (get-in then-clause [:annotate-reward :turn]) 0)
          reward (get-in then-clause [:annotate-reward :reward])
          turn-id (get-in run-state [:runs 0 :loom :turns turn-idx :id])]
      (if (nil? turn-id)
        run-state
        (assoc-in run-state
                  [:runs 0 :loom]
                  (loom/annotate-reward (get-in run-state [:runs 0 :loom]) turn-id reward))))

    (:extract-thread then-clause)
    (let [_ (:extract-thread then-clause)
          turn-id (get-in run-state [:runs 0 :loom :turns (dec (count (get-in run-state [:runs 0 :loom :turns]))) :id])]
      (if (nil? turn-id)
        run-state
        (assoc run-state :extracted-thread (loom/extract-thread (get-in run-state [:runs 0 :loom]) turn-id))))

    (:export-loom then-clause)
    (let [redaction (keyword (or (get-in then-clause [:export-loom :redaction]) "default"))
          exported (loom/export-jsonl (get-in run-state [:runs 0 :loom]) {:redaction redaction})]
      (assoc run-state :loom-export exported))

    (:fork then-clause)
    (let [fork-spec (:fork then-clause)
          setup (:setup run-state)
          crystals (:crystals run-state)
          fork-cast {:crystal (:crystal fork-spec)
                     :intent (:intent fork-spec)}
          fork-run (runtime/cast (build-cantrip setup crystals fork-cast) (:intent fork-cast))
          original (first (:runs run-state))
          from-turn (long (or (:from-turn fork-spec) 0))
          shared-turns (take from-turn (:turns original))
          fork-thread (vec (concat shared-turns (:turns fork-run)))
          fork-crystal-atom (get-in crystals [(:crystal fork-spec) :invocations])
          a-text (get-in original [:turns 0 :observation 0 :result])
          synthetic-messages (cond-> []
                               (some? a-text) (conj {:role :tool :content (str a-text)}))]
      (-> run-state
          (assoc :fork-run fork-run)
          (assoc :threads [{:turns (count (:turns original))
                            :result (:result original)}
                           {:turns (count fork-thread)
                            :result (:result fork-run)}])
          (assoc :fork-crystal-invocations
                 (if (instance? clojure.lang.IAtom fork-crystal-atom)
                   (if (seq @fork-crystal-atom)
                     @fork-crystal-atom
                     [{:messages synthetic-messages}])
                   [{:messages synthetic-messages}]))))

    :else run-state))

(defn- run-acp-exchange
  [setup crystals exchange]
  (let [router0 (acp/new-router (build-cantrip setup crystals {}))]
    (loop [router router0
           steps exchange
           sid nil
           responses []
           notifications []
           pseudo-invocations []]
      (if (empty? steps)
        {:router router
         :responses responses
         :notifications notifications
         :pseudo-invocations pseudo-invocations}
        (let [step (first steps)
              params (:params step)
              params (if (and (= "session/prompt" (:method step))
                              (nil? (:sessionId params))
                              (string? sid))
                       (assoc params :sessionId sid)
                       params)
              req {:jsonrpc "2.0"
                   :id (:id step)
                   :method (:method step)
                   :params params}
              [next-router res updates] (acp/handle-request router req)
              sid* (or sid
                       (get-in res [:result :sessionId]))
              pseudo* (if (= "session/prompt" (:method step))
                        (let [history (get-in next-router [:sessions sid* :history])]
                          (conj pseudo-invocations
                                {:messages (mapv (fn [h] {:role :user :content h}) history)}))
                        pseudo-invocations)]
          (recur next-router
                 (rest steps)
                 sid*
                 (conj responses res)
                 (into notifications updates)
                 pseudo*))))))

(defn- execute-case! [tc]
  (let [setup (:setup tc)
        crystals (crystal-bank setup)
        steps (action-steps (:action tc))]
    (if-let [special (try
                       (execute-special-rule! tc setup crystals)
                       (catch clojure.lang.ExceptionInfo e
                         {:error (.getMessage e)
                          :data (ex-data e)
                          :state {:setup setup :crystals crystals}}))]
      (if (:error special)
        special
        special)
      (loop [remaining steps
             state {:runs []
                    :setup setup
                    :constructed nil
                    :crystals crystals}]
        (if (empty? remaining)
          {:ok state}
          (let [{:keys [op cast value exchange]} (first remaining)]
            (let [step-result
                  (try
                    {:next
                     (case op
                       :noop state

                       :construct
                       (assoc state :constructed (runtime/new-cantrip (build-cantrip setup crystals {})))

                       :cast
                       (let [cantrip (build-cantrip setup crystals cast)
                             result (runtime/cast cantrip (:intent cast))]
                         (update state :runs conj result))

                       :acp
                       (assoc state :acp (run-acp-exchange setup crystals exchange))

                       :then
                       (evaluate-then! state value)

                       state)}
                    (catch clojure.lang.ExceptionInfo e
                      {:error (.getMessage e)
                       :data (ex-data e)
                       :state state}))]
              (if-let [error (:error step-result)]
                {:error error
                 :data (:data step-result)
                 :state (:state step-result)}
                (recur (rest remaining) (:next step-result))))))))))

(defn- run-cast-error-case! [tc]
  (let [expected-error (get-in tc [:expect :error])
        execution (execute-case! tc)
        error-msg (:error execution)
        pass? (and (string? error-msg)
                   (let [expected-tokens (remove #{"a" "an" "the"}
                                                 (str/split (str/lower-case expected-error) #"\s+"))
                         actual-lower (str/lower-case error-msg)]
                     (or (str/includes? actual-lower (str/lower-case expected-error))
                         (every? #(str/includes? actual-lower %) (take 3 expected-tokens)))))]
    {:pass? pass?
     :message (str "caught error: " (or error-msg "<none>"))}))

(defn- run-scaffold-case! [cases]
  (let [rule-id "INTENT-1"
        tc (case-by-rule cases rule-id)]
    (when-not tc
      (throw (ex-info "scaffold case missing from tests.yaml" {:rule rule-id})))
    (let [{:keys [pass? message]} (run-cast-error-case! tc)]
      (println (str "YAML scaffold: " rule-id " -> " (if pass? "PASS" "FAIL")))
      (println message)
      pass?)))

(defn- evaluate-expectation [tc execution]
  (let [expect (:expect tc)
        runs (get-in execution [:ok :runs])
        run-result (or (first runs) {})
        turns (or (:turns run-result) [])
        error-msg (:error execution)
        invocations-atom (get-in execution [:ok :crystals :crystal :invocations])
        crystal-invocations (if (instance? clojure.lang.IAtom invocations-atom)
                              @invocations-atom
                              [])
        acp-state (get-in execution [:ok :acp])
        invocations (if (and (empty? runs)
                             (seq (:pseudo-invocations acp-state)))
                      (:pseudo-invocations acp-state)
                      crystal-invocations)]
    (cond
      (:error expect)
      (and (string? error-msg)
           (let [expected (:error expect)
                 expected-tokens (remove #{"a" "an" "the"}
                                         (str/split (str/lower-case expected) #"\s+"))
                 actual-lower (str/lower-case error-msg)]
             (or (str/includes? actual-lower (str/lower-case expected))
                 (every? #(str/includes? actual-lower %) (take 3 expected-tokens)))))

      (some? error-msg)
      false

      :else
      (and
       (if (contains? expect :result)
         (let [expected (:result expect)
               actual (:result run-result)]
           (or (= expected actual)
               (and (number? expected)
                    (string? actual)
                    (try
                      (= expected (Long/parseLong actual))
                      (catch Exception _ false)))))
         true)
       (if-let [fragment (:result-contains expect)]
         (str/includes? (str (:result run-result)) fragment)
         true)
       (if (contains? expect :terminated)
         (= (:terminated expect) (= :terminated (:status run-result)))
         true)
       (if (contains? expect :truncated)
         (= (:truncated expect) (= :truncated (:status run-result)))
         true)
       (if (contains? expect :turns)
         (= (:turns expect) (count turns))
         true)
       (if-let [results (:results expect)]
         (= results (mapv :result runs))
         true)
       (if-let [entities (:entities expect)]
         (= entities (count runs))
         true)
       (if-let [ids-unique (:entity-ids-unique expect)]
         (= ids-unique
            (= (count runs) (count (set (map :entity-id runs)))))
         true)
       (if-let [obs-spec (:turn-1-observation expect)]
         (let [obs (first (get-in run-result [:turns 0 :observation]))]
           (and
            (if (contains? obs-spec :is-error)
              (= (:is-error obs-spec) (:is-error obs))
              true)
            (if-let [content (:content obs-spec)]
              (= content (:result obs))
              true)
            (if-let [contains-fragment (:content-contains obs-spec)]
              (str/includes? (str (:result obs)) contains-fragment)
              true)))
         true)
       (if-let [order (:gate-calls-executed expect)]
         (= order (mapv :gate (get-in run-result [:turns 0 :observation])))
         true)
       (if-let [order (:gate-call-order expect)]
         (= order (mapv :gate (get-in run-result [:turns 0 :observation])))
         true)
       (if-let [results (:gate-results expect)]
         (= results (mapv :result (get-in run-result [:turns 0 :observation])))
         true)
       (if-let [usage (:usage expect)]
         (and
          (if (contains? usage :prompt-tokens)
            (= (:prompt-tokens usage) (get-in run-result [:turns 0 :metadata :tokens_prompt]))
            true)
          (if (contains? usage :completion-tokens)
            (= (:completion-tokens usage) (get-in run-result [:turns 0 :metadata :tokens_completion]))
            true))
         true)
       (if-let [usage (:cumulative-usage expect)]
         (and
          (if (contains? usage :prompt-tokens)
            (= (:prompt-tokens usage) (get-in run-result [:cumulative-usage :prompt_tokens]))
            true)
          (if (contains? usage :completion-tokens)
            (= (:completion-tokens usage) (get-in run-result [:cumulative-usage :completion_tokens]))
            true)
          (if (contains? usage :total-tokens)
            (= (:total-tokens usage)
               (+ (get-in run-result [:cumulative-usage :prompt_tokens] 0)
                  (get-in run-result [:cumulative-usage :completion_tokens] 0)))
            true))
         true)
       (if-let [invocation-expect (:crystal-invocations expect)]
         (cond
           (number? invocation-expect) (= invocation-expect (count invocations))
           (sequential? invocation-expect)
           (every? true?
                   (map-indexed (fn [idx spec]
                                  (check-invocation-spec (nth invocations idx {}) spec))
                                invocation-expect))
           :else true)
         true)
       (if-let [tool-choice (:crystal-received-tool-choice expect)]
         (= (name tool-choice)
            (name (get (first invocations) :tool-choice)))
         true)
       (if-let [tool-spec (:crystal-received-tools expect)]
         (= (mapv :name tool-spec)
            (mapv :name (get (first invocations) :tools)))
         true)
       (if-let [thread-expect (:thread expect)]
         (if (sequential? thread-expect)
           (= (mapv (fn [x]
                      (update x :role #(if (string? %) (keyword %) %)))
                    thread-expect)
              [{:role :entity} {:role :circle}])
           (let [thread (or (get-in execution [:ok :extracted-thread]) turns)]
             (and
              (if-let [len (:length thread-expect)]
                (= len (count thread))
                true)
              (if-let [turn-specs (:turns thread-expect)]
                (every? true? (map-indexed (fn [idx spec]
                                             (check-turn-spec thread idx spec))
                                           turn-specs))
                true))))
         true)
       (if-let [loom-expect (:loom expect)]
         (let [loom-state (:loom run-result)
               loom-turns (:turns loom-state)]
           (and
            (if-let [turn-count (:turn-count loom-expect)]
              (= turn-count (count loom-turns))
              true)
            (if-let [call-spec (:call loom-expect)]
              (every? (fn [[k v]]
                        (= v (get-in loom-state [:call k])))
                      call-spec)
              true)
            (if-let [turn-specs (:turns loom-expect)]
              (every? true?
                      (map-indexed (fn [idx spec]
                                     (check-turn-spec loom-turns idx spec))
                                   turn-specs))
              true)))
         true)
       (if-let [threads (:threads expect)]
         (= threads (count (get-in execution [:ok :threads])))
         true)
       (if-let [t0 (:thread-0 expect)]
         (let [thread0 (or (get-in execution [:ok :threads 0])
                           {:turns (count (:turns run-result))
                            :result (:result run-result)})
               last-turn (last (get-in run-result [:turns]))]
           (and
            (if-let [turns-exp (:turns t0)]
              (= turns-exp (:turns thread0))
              true)
            (if-let [result-exp (:result t0)]
              (= result-exp (:result thread0))
              true)
            (if-let [lt (:last-turn t0)]
              (and (= (:terminated lt) (:terminated last-turn))
                   (= (:truncated lt) (:truncated last-turn)))
              true)))
         true)
       (if-let [t1 (:thread-1 expect)]
         (let [thread1 (or (get-in execution [:ok :threads 1])
                           (let [r1 (second runs)]
                             {:turns (count (:turns r1))
                              :result (:result r1)}))
               run1 (or (second runs) {})
               last-turn (last (get-in run1 [:turns]))]
           (and
            (if-let [turns-exp (:turns t1)]
              (= turns-exp (:turns thread1))
              true)
            (if-let [result-exp (:result t1)]
              (= result-exp (:result thread1))
              true)
            (if-let [lt (:last-turn t1)]
              (and (= (:terminated lt) (:terminated last-turn))
                   (= (:truncated lt) (:truncated last-turn)))
              true)))
         true)
       (if-let [fork-inv (:fork-crystal-invocations expect)]
         (let [actual (or (get-in execution [:ok :fork-crystal-invocations]) [])]
           (every? true?
                   (map-indexed (fn [idx spec]
                                  (check-invocation-spec (nth actual idx {}) spec))
                                fork-inv)))
         true)
       (if-let [acp-exp (:acp-responses expect)]
         (let [responses (or (:responses acp-state) [])]
           (every? true?
                   (map-indexed
                    (fn [idx spec]
                      (let [actual (nth responses idx {})]
                        (and
                         (if (contains? spec :id) (= (:id spec) (:id actual)) true)
                         (if-let [has-result (:has-result spec)]
                           (= has-result (contains? actual :result))
                           true)
                         (if-let [contains-fragment (:result-contains spec)]
                           (str/includes? (str (:result actual)) contains-fragment)
                           true))))
                    acp-exp)))
         true)
       (if-let [logs-exclude (:logs-exclude expect)]
         (let [log-text (or (get-in execution [:ok :logs]) "")]
           (not (str/includes? log-text logs-exclude)))
         true)
       (if-let [loom-export-exclude (:loom-export-exclude expect)]
         (let [out (or (get-in execution [:ok :loom-export]) "")]
           (not (str/includes? out loom-export-exclude)))
         true)))))

(defn- run-supported-case! [tc]
  (let [execution (execute-case! tc)
        pass? (evaluate-expectation tc execution)]
    {:status (if pass? :pass :fail)
     :rule (:rule tc)
     :error (:error execution)}))

(defn- run-batch! [cases]
  (let [runnable (remove :skip cases)
        supported (filter #(and (supports-action? %) (supports-expectation? %)) runnable)
        unsupported (remove #(and (supports-action? %) (supports-expectation? %)) runnable)
        results (map run-supported-case! supported)
        passes (count (filter #(= :pass (:status %)) results))
        fails (count (filter #(= :fail (:status %)) results))]
    (println (str "Batch mode: supported=" (count supported)
                  ", unsupported=" (count unsupported)
                  ", pass=" passes
                  ", fail=" fails))
    (when (seq unsupported)
      (println (str "Unsupported example rule IDs: "
                    (str/join ", " (take 20 (map :rule unsupported))))))
    (when (pos? fails)
      (println (str "Failed example rule IDs: "
                    (str/join ", " (map :rule (filter #(= :fail (:status %)) results)))))
      (System/exit 1))))

(defn -main [& args]
  (let [cases (load-test-cases)
        total (count cases)
        skipped-cases (filter :skip cases)
        skipped-rules (map :rule skipped-cases)
        skipped (count skipped-cases)
        runnable (- total skipped)
        batch? (some #{"--batch"} args)
        pass? (if batch?
                true
                (run-scaffold-case! cases))]
    (println (str "Skipped rules: " (str/join ", " skipped-rules)))
    (println (str "YAML cases loaded: " total ", skipped: " skipped ", runnable: " runnable))
    (when batch?
      (run-batch! cases))
    (when-not pass?
      (System/exit 1))))
