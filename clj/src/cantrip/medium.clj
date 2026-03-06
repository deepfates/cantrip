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
        ctx (sci/init {:bindings (merge base-bindings bindings)
                       :classes {'Exception Exception
                                 'Throwable Throwable
                                 'RuntimeException RuntimeException
                                 'clojure.lang.ExceptionInfo clojure.lang.ExceptionInfo}})]
    (doseq [snippet prior-snippets]
      (sci/eval-string* ctx snippet))
    (let [prior-count (count @emitted)]
      (sci/eval-string* ctx code)
      (subvec (vec @emitted) prior-count))))

(defn- host-code-bindings
  [dependencies]
  (merge
   (when-let [f (:call-entity-fn dependencies)]
     {'call-agent f
      'call_entity f})
   (when-let [f (:call-entity-batch-fn dependencies)]
     {'call-agent-batch f
      'call_entity_batch f})))

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
  "Returns medium capability description for llm context assembly."
  (fn [circle _dependencies] (:medium circle)))

(defn- format-gate-doc
  "Returns a one-line description of a gate for code medium capability text."
  [gate-name]
  (case gate-name
    "done"                "(submit-answer value) — complete the task and return value as the answer"
    "echo"                "(call-gate :echo {:text \"...\"}) — echo text back as an observation"
    "read"                "(call-gate :read {:path \"filename\"}) — read a file; returns its contents or error"
    "read-report"         "(call-gate :read-report {:path \"filename\"}) — read a report file"
    "compile-and-load"    "(call-gate :compile-and-load {:module \"Name\" :source \"code\"}) — compile and load a module"
    "call-entity"         "(call-agent {:intent \"task\" :cantrip cantrip-map}) — delegate to a child entity, returns its answer"
    "call-entity-batch"   "(call-agent-batch [{:intent \"task\" :cantrip c}]) — delegate multiple tasks, returns vector of answers"
    (str "(call-gate :" gate-name " {:key \"value\"}) — invoke the " gate-name " gate")))

(defn capability-text
  "Returns a capability documentation string for the given circle and medium.
   For code medium: sandbox physics + host function descriptions.
   For conversation medium: nil (gates are described via tool definitions)."
  [circle]
  (let [medium (:medium circle)]
    (when (or (= medium :code) (= medium :minecraft))
      (let [gate-names (gates/gate-names (:gates circle))
            gate-lines (str/join "\n" (map #(str "- " (format-gate-doc %)) gate-names))
            medium-name (if (= medium :minecraft) "Minecraft Clojure" "Clojure")]
        (str "You write " medium-name " code that executes in a SCI (Small Clojure Interpreter) sandbox.\n"
             "Respond ONLY with code in the clojure tool. Do not write prose or markdown.\n\n"
             "### SANDBOX PHYSICS\n"
             "1. call-agent is SYNCHRONOUS — it blocks until the child finishes and returns the answer as a string.\n"
             "2. submit-answer and call-gate EMIT — they queue actions. submit-answer completes the task.\n"
             "3. Variables defined with (def ...) persist across turns.\n"
             "4. Standard Clojure core is available (map, reduce, str, etc.).\n"
             "5. NO Java interop (no Math/exp, no .method calls, no Class/staticMethod).\n"
             "6. NO require, ns, eval, slurp, spit, or I/O.\n"
             "7. defn is available for helpers. No defprotocol, defrecord, deftype.\n\n"
             "### HOST FUNCTIONS\n"
             gate-lines "\n\n"
             "Call (submit-answer value) when finished. This is the ONLY way to complete the task.")))))

(defn tool-view
  "Returns medium-appropriate tool definitions, tool_choice, and capability text.
   Code medium: single 'clojure' tool with tool_choice required + capability text.
   Conversation medium: all gates as tools, tool_choice from identity, no capability text."
  [circle identity-config]
  (let [medium (:medium circle)]
    (if (or (= medium :code) (= medium :minecraft))
      {:tools [{:name "clojure"
                :description "Execute Clojure code in the SCI sandbox"
                :parameters {:type "object"
                             :properties {:code {:type "string"
                                                 :description "Clojure code to execute"}}
                             :required ["code"]}}]
       :tool-choice :required
       :capability-text (capability-text circle)}
      {:tools (gates/gate-tools (:gates circle))
       :tool-choice (or (:tool-choice identity-config)
                        (when (true? (:require-done-tool identity-config)) :required)
                        :auto)
       :capability-text nil})))

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

(defn- extract-code
  "Extracts executable code from an LLM utterance.
   Code may come from: (1) a 'clojure' tool call's :code arg, (2) raw content string,
   or (3) direct tool calls (legacy/FakeLLM)."
  [utterance]
  (let [tool-calls (vec (:tool-calls utterance))
        content (:content utterance)
        ;; Check for single 'clojure' tool call (the new pattern)
        clj-tool-call (first (filter #(= "clojure" (name (or (:gate %) ""))) tool-calls))
        code-from-tool (when clj-tool-call
                         (or (get-in clj-tool-call [:args :code])
                             (get-in clj-tool-call [:args "code"])))]
    (cond
      ;; New pattern: clojure tool call with code arg
      (string? code-from-tool)
      {:code code-from-tool :tool-call-id (:id clj-tool-call) :mode :tool}
      ;; Legacy pattern: raw content string (FakeLLM or old format)
      (and (empty? tool-calls) (string? content))
      {:code content :mode :content}
      ;; Direct gate tool calls (conversation-style, FakeLLM)
      (seq tool-calls)
      {:tool-calls tool-calls :mode :direct}
      :else nil)))

(defmethod execute-utterance :code
  [circle utterance dependencies]
  (let [extracted (extract-code utterance)
        prior-turns (or (:prior-turns dependencies) [])
        code-bindings (host-code-bindings dependencies)]
    (case (:mode extracted)
      (:tool :content)
      (try
        (let [code (:code extracted)
              snippets (->> prior-turns
                            (map (fn [turn]
                                   ;; Extract code from prior turns too (may be in tool args or content)
                                   (let [prev-extracted (extract-code (:utterance turn))]
                                     (when (#{:tool :content} (:mode prev-extracted))
                                       (:code prev-extracted)))))
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

      :direct
      (circle/execute-tool-calls circle (:tool-calls extracted) dependencies)

      ;; Fallback: empty utterance
      {:observation []
       :terminated? false
       :result nil})))

(defmethod execute-utterance :minecraft
  [circle utterance dependencies]
  (let [extracted (extract-code utterance)
        code-bindings (merge (minecraft-bindings dependencies)
                             (host-code-bindings dependencies))]
    (case (:mode extracted)
      (:tool :content)
      (try
        (let [code (:code extracted)]
          (validate-code! circle [] code)
          (circle/execute-tool-calls circle
                                     (eval-with-timeout! circle
                                                         #(eval-script->tool-calls [] code code-bindings))
                                     dependencies))
        (catch Exception e
          {:observation [{:gate "minecraft"
                          :arguments "{}"
                          :result (str "minecraft execution error: " (.getMessage e))
                          :is-error true}]
           :terminated? false
           :result nil}))

      :direct
      (circle/execute-tool-calls circle (:tool-calls extracted) dependencies)

      {:observation []
       :terminated? false
       :result nil})))
