(ns cantrip.crystal)

(defn- tool-call-ids [tool-calls]
  (map :id tool-calls))

(defn- ensure-tool-calls-have-ids! [tool-calls]
  (doseq [call tool-calls]
    (when-not (string? (:id call))
      (throw (ex-info "tool calls must have unique IDs"
                      {:rule "CRYSTAL-4" :tool-call call}))))
  (let [ids (tool-call-ids tool-calls)
        unique-count (count (set ids))]
    (when-not (= unique-count (count ids))
      (throw (ex-info "duplicate tool call ID"
                      {:rule "CRYSTAL-4" :ids ids}))))
  tool-calls)

(defn- ensure-required-shape! [response]
  (when-not (or (string? (:content response))
                (seq (:tool-calls response)))
    (throw (ex-info "crystal returned neither content nor tool_calls"
                    {:rule "CRYSTAL-3"})))
  response)

(defn- ensure-tool-choice-required! [response tool-choice]
  (when (and (= tool-choice :required)
             (empty? (:tool-calls response)))
    (throw (ex-info "tool_choice required but no tool calls returned"
                    {:rule "CRYSTAL-5"})))
  response)

(defn- ensure-tool-result-linkage! [response previous-tool-call-ids]
  (let [known-ids (set previous-tool-call-ids)
        tool-results (:tool-results response)]
    (doseq [tool-result tool-results]
      (when-not (contains? known-ids (:tool-call-id tool-result))
        (throw (ex-info "tool result without matching tool call"
                        {:rule "CRYSTAL-7"
                         :tool-result tool-result
                         :known-ids known-ids}))))
    response))

(defn- normalize-tool-call [call]
  {:id (:id call)
   :gate (or (:gate call) (:name call))
   :args (or (:args call) (:arguments call) {})})

(defn- normalize-response [response]
  (-> response
      (update :tool-calls #(mapv normalize-tool-call (or % [])))
      (update :tool-results #(vec (or % [])))))

(defn- record-invocation!
  [crystal invocation]
  (when (and (:record-inputs crystal)
             (instance? clojure.lang.IAtom (:invocations crystal)))
    (swap! (:invocations crystal) conj invocation)))

(defn- response-index [crystal turn-index]
  (if (and (:responses-by-invocation crystal)
           (instance? clojure.lang.IAtom (:invocations crystal)))
    (max 0 (dec (count @(:invocations crystal))))
    turn-index))

(defn query
  "Queries the configured crystal. For now supports deterministic fake responses."
  [crystal {:keys [turn-index messages tools tool-choice previous-tool-call-ids]}]
  (record-invocation! crystal {:messages (vec messages)
                               :tools (vec tools)
                               :tool-choice tool-choice})
  (let [idx (response-index crystal turn-index)
        response (or (get (:responses crystal) idx) {})
        _ (when-let [err (:error response)]
            (throw (ex-info (or (:message err) "crystal provider error")
                            {:status (:status err)
                             :provider-error err})))
        normalized (normalize-response response)]
    (-> normalized
        ensure-required-shape!
        (update :tool-calls #(do (ensure-tool-calls-have-ids! %) %))
        (ensure-tool-choice-required! tool-choice)
        (ensure-tool-result-linkage! previous-tool-call-ids))))
