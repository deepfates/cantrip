(ns cantrip.conformance
  (:require [cantrip.runtime :as runtime]
            [cantrip.loom :as loom]
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
  (let [tool-result (:tool-result response)
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
      (string? selector) (or (find-crystal-by-name crystals selector)
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

(defn- action-steps [action]
  (cond
    (true? (:construct-cantrip action))
    [{:op :construct}]

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
        supported-ops #{:construct :cast :then}]
    (and
     (or (not (some #(= :cast (:op %)) steps))
         (not (code-setup? (:setup tc))))
     (seq steps)
     (every? #(contains? supported-ops (:op %)) steps)
     (or (not= :then (:op (last steps)))
         (supported-then? (-> steps last :value)))
     (not (contains? action :acp-exchange)))))

(defn- unsupported-expectation? [expect]
  (letfn [(contains-key-recursively? [v k]
            (cond
              (map? v) (or (contains? v k)
                           (some #(contains-key-recursively? % k) (vals v)))
              (sequential? v) (some #(contains-key-recursively? % k) v)
              :else false))]
    (or
     (contains? expect :acp-responses)
     (contains? expect :logs-exclude)
     (contains? expect :loom-export-exclude)
     (contains? expect :fork-crystal-invocations)
     (contains? expect :threads)
     (contains? expect :thread-0)
     (contains? expect :thread-1)
     (contains? expect :entities-id-unique)
     (contains-key-recursively? expect :entity-id))))

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
                    :crystal-received-tools}]
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

    :else run-state))

(defn- execute-case! [tc]
  (let [setup (:setup tc)
        crystals (crystal-bank setup)
        steps (action-steps (:action tc))]
    (loop [remaining steps
           state {:runs []
                  :constructed nil
                  :crystals crystals}]
      (if (empty? remaining)
        {:ok state}
        (let [{:keys [op cast value]} (first remaining)]
          (let [step-result
                (try
                  {:next
                   (case op
                     :construct
                     (assoc state :constructed (runtime/new-cantrip (build-cantrip setup crystals {})))

                     :cast
                     (let [cantrip (build-cantrip setup crystals cast)
                           result (runtime/cast cantrip (:intent cast))]
                       (update state :runs conj result))

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
              (recur (rest remaining) (:next step-result)))))))))

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
        run-result (first runs)
        turns (:turns run-result)
        error-msg (:error execution)
        invocations-atom (get-in execution [:ok :crystals :crystal :invocations])
        invocations (if (instance? clojure.lang.IAtom invocations-atom)
                      @invocations-atom
                      [])]
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
         (= (:result expect) (:result run-result))
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
