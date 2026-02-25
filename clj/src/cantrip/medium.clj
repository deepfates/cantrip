(ns cantrip.medium
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]
            [clojure.string :as str]
            [sci.core :as sci]))

(defn- eval-script->tool-calls
  [prior-snippets code bindings]
  (let [emitted (atom [])
        next-id (fn [] (str "code_call_" (inc (count @emitted))))
        emit! (fn [gate args]
                (swap! emitted conj {:id (next-id)
                                     :gate gate
                                     :args (or args {})}))
        submit! (fn [answer]
                  (emit! :done {:answer (str answer)}))
        call-gate! (fn
                     ([gate] (emit! gate {}))
                     ([gate args] (emit! gate args)))
        base-bindings {'submit-answer submit!
                       'submit_answer submit!
                       'call-gate call-gate!
                       'call_gate call-gate!}
        ctx (sci/init {:bindings (merge base-bindings bindings)})]
    (doseq [snippet prior-snippets]
      (sci/eval-string* ctx snippet))
    (let [prior-count (count @emitted)]
      (sci/eval-string* ctx code)
      (subvec (vec @emitted) prior-count))))

(defn- host-code-bindings
  [dependencies]
  (merge
   (when-let [f (:call-agent-fn dependencies)]
     {'call-agent f
      'call_agent f})
   (when-let [f (:call-agent-batch-fn dependencies)]
     {'call-agent-batch f
      'call_agent_batch f})))

(defn- ward-value
  [circle k]
  (some #(or (get % k) (get % (keyword (str/replace (name k) "-" "_"))))
        (:wards circle)))

(defn- allow-require?
  [circle]
  (true? (ward-value circle :allow-require)))

(defn- max-forms
  [circle]
  (ward-value circle :max-forms))

(defn- max-eval-ms
  [circle]
  (ward-value circle :max-eval-ms))

(defn- count-forms
  [code]
  (let [reader (java.io.PushbackReader. (java.io.StringReader. code))]
    (loop [n 0]
      (let [form (read {:eof ::eof} reader)]
        (if (= ::eof form)
          n
          (recur (inc n)))))))

(defn- validate-code!
  [circle snippets code]
  (let [all-code (str/join "\n" (concat snippets [code]))
        allow-req? (allow-require? circle)
        forms-limit (max-forms circle)]
    (when (and (not allow-req?)
               (re-find #"(?i)\(\s*require\b|(?i)\(\s*ns\b" all-code))
      (throw (ex-info "code execution blocked: require/ns not allowed"
                      {:ward :allow-require :value false})))
    (when (re-find #"(?i)\b(load-string|eval|slurp|spit|clojure\.java\.shell|System/exit)\b" all-code)
      (throw (ex-info "code execution blocked: forbidden symbol"
                      {:ward :sandbox :reason :forbidden-symbol})))
    (when (and (some? forms-limit)
               (> (count-forms code) (long forms-limit)))
      (throw (ex-info "code execution blocked: max forms exceeded"
                      {:ward :max-forms :max-forms (long forms-limit)})))))

(defn- eval-with-timeout!
  [circle f]
  (if-let [timeout-ms (max-eval-ms circle)]
    (let [job (future (f))
          result (deref job (long timeout-ms) ::timeout)]
      (if (= ::timeout result)
        (do
          (future-cancel job)
          (throw (ex-info "code execution timeout" {:ward :max-eval-ms :max-eval-ms (long timeout-ms)})))
        result))
    (f)))

(defn- minecraft-bindings
  [deps]
  (let [player-fn (:player-fn deps)
        xyz-fn (:xyz-fn deps)
        block-fn (:block-fn deps)
        set-block-fn (:set-block-fn deps)
        allow-mutation? (true? (:allow-mutation? deps))]
    (merge
     (when player-fn
       {'player (fn [] (player-fn))})
     (when xyz-fn
       {'xyz (fn [] (xyz-fn))})
     (when block-fn
       {'block (fn
                 ([loc] (block-fn loc))
                 ([] (block-fn)))})
     (when set-block-fn
       {'set-block (fn [loc b]
                     (if allow-mutation?
                       (set-block-fn loc b)
                       (throw (ex-info "minecraft mutation not allowed"
                                       {:mutation :set-block}))))}))))

(defmulti capability-view
  "Returns medium capability description for crystal context assembly."
  (fn [circle _dependencies] (:medium circle)))

(defmulti execute-utterance
  "Executes one utterance in the configured medium."
  (fn [circle _utterance _dependencies] (:medium circle)))

(defmulti snapshot-state
  "Captures medium-local state for persistent entities."
  (fn [circle _dependencies] (:medium circle)))

(defmulti restore-state
  "Restores medium-local state into dependencies and returns restored state."
  (fn [circle _state _dependencies] (:medium circle)))

(defmethod capability-view :conversation
  [circle _]
  {:medium :conversation
   :gates (gates/gate-names (:gates circle))})

(defmethod snapshot-state :conversation
  [_ _]
  {})

(defmethod restore-state :conversation
  [_ state _]
  (or state {}))

(defmethod capability-view :code
  [circle _]
  {:medium :code
   :gates (gates/gate-names (:gates circle))
   :notes ["host-projected gates available in medium context"]})

(defmethod snapshot-state :code
  [_ _]
  {})

(defmethod restore-state :code
  [_ state _]
  (or state {}))

(defmethod capability-view :minecraft
  [circle _]
  {:medium :minecraft
   :gates (gates/gate-names (:gates circle))
   :notes ["world-facing medium via dependency context"]})

(defmethod snapshot-state :minecraft
  [_ _]
  {})

(defmethod restore-state :minecraft
  [_ state _]
  (or state {}))

(defmethod execute-utterance :conversation
  [circle utterance dependencies]
  (circle/execute-tool-calls circle (vec (:tool-calls utterance)) dependencies))

(defmethod execute-utterance :code
  [circle utterance dependencies]
  (let [tool-calls (vec (:tool-calls utterance))
        code (:content utterance)
        prior-turns (or (:prior-turns dependencies) [])
        code-bindings (host-code-bindings dependencies)]
    (if (and (empty? tool-calls) (string? code))
      (try
        (let [snippets (->> prior-turns
                            (map #(get-in % [:utterance :content]))
                            (filter string?))]
          (validate-code! circle snippets code)
          (circle/execute-tool-calls circle
                                     (eval-with-timeout! circle
                                                         #(eval-script->tool-calls snippets code code-bindings))
                                     dependencies))
        (catch Exception e
          {:observation [{:gate "code"
                          :arguments "{}"
                          :result (str "code execution error: " (.getMessage e))
                          :is-error true}]
           :terminated? false
           :result nil}))
      (circle/execute-tool-calls circle tool-calls dependencies))))

(defmethod execute-utterance :minecraft
  [circle utterance dependencies]
  (let [tool-calls (vec (:tool-calls utterance))
        code (:content utterance)
        code-bindings (merge (minecraft-bindings dependencies)
                             (host-code-bindings dependencies))]
    (if (and (empty? tool-calls) (string? code))
      (try
        (validate-code! circle [] code)
        (circle/execute-tool-calls circle
                                   (eval-with-timeout! circle
                                                       #(eval-script->tool-calls [] code code-bindings))
                                   dependencies)
        (catch Exception e
          {:observation [{:gate "minecraft"
                          :arguments "{}"
                          :result (str "minecraft execution error: " (.getMessage e))
                          :is-error true}]
           :terminated? false
           :result nil}))
      (circle/execute-tool-calls circle tool-calls dependencies))))
