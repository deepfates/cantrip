(ns cantrip.examples
  (:refer-clojure :exclude [send])
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]
            [cantrip.llm :as llm]
            [cantrip.medium :as medium]
            [cantrip.protocol.acp :as acp]
            [cantrip.runtime :as runtime]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(defn- load-dotenv!
  "Load KEY=VALUE pairs from a .env file into system properties
   (accessible via System/getProperty). Only sets vars not already
   present in the real environment."
  [path]
  (let [f (io/file path)]
    (when (.exists f)
      (doseq [line (str/split-lines (slurp f))
              :let [trimmed (str/trim line)]
              :when (and (seq trimmed)
                         (not (str/starts-with? trimmed "#"))
                         (str/includes? trimmed "="))
              :let [[k v] (str/split trimmed #"=" 2)
                    k (str/trim k)
                    v (-> (or v "") str/trim (str/replace #"^\"|\"$" ""))]
              :when (and (seq k)
                         (nil? (System/getenv k)))]
        (System/setProperty k v)))))

(defonce ^:private _dotenv-loaded
  (load-dotenv! (str (System/getProperty "user.dir") "/.env")))

(defn- env
  "Read an environment variable, falling back to system property (from .env)."
  [k]
  (or (System/getenv k) (System/getProperty k)))

(defn- resolve-llm-config
  "Resolve LLM config. :scripted mode uses :fake provider.
   Default mode reads env vars + .env fallback and raises if missing.
   :real mode reads only real env vars (no .env) — used by tests to verify
   the no-silent-fallback requirement."
  [opts scripted-responses]
  (case (:mode opts)
    :scripted {:provider :fake :responses scripted-responses}
    :real (let [model (or (System/getenv "OPENAI_MODEL")
                          (System/getenv "CANTRIP_OPENAI_MODEL"))
                api-key (or (System/getenv "OPENAI_API_KEY")
                            (System/getenv "CANTRIP_OPENAI_API_KEY"))
                base-url (or (System/getenv "OPENAI_BASE_URL")
                             (System/getenv "CANTRIP_OPENAI_BASE_URL")
                             "https://api.openai.com/v1")]
            (when-not model
              (throw (ex-info "Missing OPENAI_MODEL env var" {:rule "ENV-1"})))
            (when-not api-key
              (throw (ex-info "Missing OPENAI_API_KEY env var" {:rule "ENV-1"})))
            {:provider :openai :model model :api-key api-key :base-url base-url})
    ;; default: use env vars + .env fallback
    (let [model (or (env "OPENAI_MODEL")
                    (env "CANTRIP_OPENAI_MODEL"))
          api-key (or (env "OPENAI_API_KEY")
                      (env "CANTRIP_OPENAI_API_KEY"))
          base-url (or (env "OPENAI_BASE_URL")
                       (env "CANTRIP_OPENAI_BASE_URL")
                       "https://api.openai.com/v1")]
      (when-not model
        (throw (ex-info "Missing OPENAI_MODEL env var. Set it in .env or environment." {:rule "ENV-1"})))
      (when-not api-key
        (throw (ex-info "Missing OPENAI_API_KEY env var. Set it in .env or environment." {:rule "ENV-1"})))
      {:provider :openai :model model :api-key api-key :base-url base-url})))

;; ── Example 01: LLM Query ──────────────────────────────────────────────────

(defn example-01-llm-query
  "Pattern 01: one raw LLM query. Stateless round-trip only (LLM-1, LLM-3).
   No circle, no loop, no entity — just a single question and answer."
  ([] (example-01-llm-query {}))
  ([{:as opts :keys [llm-config]}]
   (let [llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:content "Revenue grew 14% QoQ driven by enterprise expansion, while churn improved by 2pp suggesting stronger product-market fit in the mid-market segment."}]))
         query {:turn-index 0
                :messages [{:role :user
                            :content "Summarize this trend: Revenue up 14%, churn down 2 points. One paragraph, focus on what it means for the business."}]
                :tools []
                :tool-choice :none
                :previous-tool-call-ids []}
         response (llm/query llm-cfg query)]
     ;; ── Narrative ──
     (println "=== Pattern 01: LLM Query ===")
     (println "A plain LLM call. No circle, no loop, no entity.")
     (println "This is the simplest possible interaction: one question in, one answer out.\n")
     (println "Intent:" (:content (first (:messages query))))
     (println "Response:" (:content response))
     (println "\nNo state was created. The LLM is stateless (LLM-1).")
     (println "If you called this again with the same input, it would not remember this exchange (LLM-3).")
     {:pattern 1
      :llm llm-cfg
      :query query
      :response response})))

;; ── Example 02: Gate ────────────────────────────────────────────────────────

(defn example-02-gate
  "Pattern 02: gates are callable functions with metadata; done is special (CIRCLE-1, LOOP-3, LOOP-7).
   Gates define the tools an LLM can call. The done gate is mandatory and terminates the loop."
  []
  (let [;; Define two gates: echo (for logging observations) and done (for termination).
        ;; In a real system, gates might be :query-database, :send-alert, :generate-report.
        gate-list [{:name :echo
                    :parameters {:type "object"
                                 :properties {:text {:type "string"}}
                                 :required ["text"]}}
                   :done]
        tools (gates/gate-tools gate-list)
        ;; A circle config using these gates with a max-turns ward
        circle-cfg {:medium :conversation
                    :gates gate-list
                    :wards [{:max-turns 3}]}
        ;; Execute an echo gate call — simulates the LLM logging a financial observation
        echo-exec (circle/execute-tool-calls
                   circle-cfg
                   [{:id "call_1" :gate :echo :args {:text "Q3 revenue: $4.2M (+14% QoQ)"}}])
        ;; Execute done — this terminates the loop. Any calls after done are dropped (LOOP-7).
        done-exec (circle/execute-tool-calls
                   circle-cfg
                   [{:id "call_2" :gate :done :args {:answer "Analysis complete: revenue trend is positive"}}
                    {:id "call_3" :gate :echo :args {:text "should not run"}}])
        ;; Malformed done (missing required 'answer' arg) — must produce an error, not terminate
        malformed-done (circle/execute-tool-calls
                        circle-cfg
                        [{:id "call_4" :gate :done :args {}}])]
    ;; ── Narrative ──
    (println "=== Pattern 02: Gate Execution ===")
    (println "Gates are the tools an LLM can call inside a circle.")
    (println "Every circle MUST include :done (CIRCLE-1). Done terminates the loop.\n")
    (println "Available tools:" (mapv :name tools))
    (println "\nEcho gate executed with financial data:")
    (println "  Input: Q3 revenue: $4.2M (+14% QoQ)")
    (println "  Error?" (get-in echo-exec [:observation 0 :is-error]))
    (println "\nDone gate terminates the loop (LOOP-7):")
    (println "  Terminated?" (:terminated? done-exec))
    (println "  Any calls after done are silently dropped.")
    (println "\nMalformed done (empty args) is an error, NOT a termination:")
    (println "  Error?" (get-in malformed-done [:observation 0 :is-error]))
    (println "  Terminated?" (:terminated? malformed-done))
    {:pattern 2
     :tools tools
     :echo-exec echo-exec
     :done-exec done-exec
     :malformed-done malformed-done}))

;; ── Example 03: Circle ─────────────────────────────────────────────────────

(defn example-03-circle
  "Pattern 03: circle construction and invariant failures (CIRCLE-1, CIRCLE-2, CANTRIP-1).
   A circle defines the action space: medium + gates + wards. Construction validates invariants."
  []
  (let [;; A valid circle for a SaaS metrics analyst
        valid-cantrip {:llm {:provider :fake :responses []}
                       :identity {:system-prompt "You are a SaaS metrics analyst. Examine revenue, churn, and expansion data. Use echo to log observations, then call done with your conclusion."}
                       :circle {:medium :conversation
                                :gates [:done :echo]
                                :wards [{:max-turns 2}]}}
        valid (runtime/new-cantrip valid-cantrip)
        ;; Attempt to build a circle without :done — must fail with CIRCLE-1
        missing-done (try
                       (runtime/new-cantrip
                        {:llm {:provider :fake}
                         :identity {:system-prompt "Revenue analyst without done gate"}
                         :circle {:medium :conversation
                                  :gates [:echo]
                                  :wards [{:max-turns 2}]}})
                       (catch clojure.lang.ExceptionInfo e
                         {:message (.getMessage e)
                          :rule (:rule (ex-data e))}))
        ;; Attempt to build a circle with empty wards — must fail with CIRCLE-2
        missing-wards (try
                        (runtime/new-cantrip
                         {:llm {:provider :fake}
                          :identity {:system-prompt "Analyst with no safety wards"}
                          :circle {:medium :conversation
                                   :gates [:done]
                                   :wards []}})
                        (catch clojure.lang.ExceptionInfo e
                          {:message (.getMessage e)
                           :rule (:rule (ex-data e))}))]
    ;; ── Narrative ──
    (println "=== Pattern 03: Circle Construction ===")
    (println "A circle is the action space boundary: A = M U G - W")
    (println "Construction enforces two hard invariants:\n")
    (println "Valid circle created with gates:" (get-in valid [:circle :gates]))
    (println "\nInvariant CIRCLE-1 — done gate required:")
    (println "  Attempted gates [:echo] without :done")
    (println "  Result:" (:message missing-done) "-> rule" (:rule missing-done))
    (println "\nInvariant CIRCLE-2 — at least one ward required:")
    (println "  Attempted empty wards []")
    (println "  Result:" (:message missing-wards) "-> rule" (:rule missing-wards))
    (println "\nThese are construction-time rejections. No LLM call is made.")
    {:pattern 3
     :valid valid
     :missing-done missing-done
     :missing-wards missing-wards}))

;; ── Example 04: Cantrip ────────────────────────────────────────────────────

(defn example-04-cantrip
  "Pattern 04: cantrip = llm + identity + circle; each cast is independent (CANTRIP-1, CANTRIP-2, INTENT-1).
   Two separate casts from the same cantrip produce independent entities with no shared state."
  ([] (example-04-cantrip {}))
  ([{:as opts :keys [llm-config]}]
   (let [llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:tool-calls [{:id "c1" :gate :done :args {:answer "The key Q3 revenue driver was enterprise seat expansion, accounting for 62% of new ARR."}}]}
                                             {:tool-calls [{:id "c2" :gate :done :args {:answer "The biggest churn risk is in the SMB segment where 30-day retention dropped 8pp in Q3."}}]}]))
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You are a SaaS analyst. Answer business questions concisely. You have one tool: done(answer). Call done(answer) with your analysis."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 4} {:require-done-tool true}]}}
         ;; Two independent casts from the same cantrip template
         first-run (runtime/cast cantrip "Identify the key revenue driver in Q3. Call done(answer) with your analysis.")
         second-run (runtime/cast cantrip "What's the biggest risk in our churn data? Call done(answer) with your analysis.")]
     ;; ── Narrative ──
     (println "=== Pattern 04: Cantrip (Two Independent Casts) ===")
     (println "A cantrip is a reusable template: llm + identity + circle.")
     (println "Each cast produces a fresh entity with its own loom (CANTRIP-2).\n")
     (println "Cast 1 — Revenue driver analysis:")
     (println "  Status:" (:status first-run))
     (println "  Result:" (:result first-run))
     (println "\nCast 2 — Churn risk analysis:")
     (println "  Status:" (:status second-run))
     (println "  Result:" (:result second-run))
     (println "\nIndependent entity IDs?" (not= (:entity-id first-run) (:entity-id second-run)))
     (println "The two casts share no state. Each got its own loop, its own loom.")
     {:pattern 4
      :cantrip cantrip
      :first-run first-run
      :second-run second-run
      :independent-entity-ids (not= (:entity-id first-run) (:entity-id second-run))})))

;; ── Example 05: Wards ──────────────────────────────────────────────────────

(defn example-05-wards
  "Pattern 05: ward composition law (min for numeric, OR for boolean) + truncation (WARD-1, CIRCLE-2).
   Wards are safety boundaries. When multiple wards apply, the strictest wins."
  ([] (example-05-wards {}))
  ([{:as opts :keys [llm-config]}]
   (let [;; Multiple wards compose: numeric takes min, boolean takes OR
         ward-stack [{:max-turns 50}
                     {:max-turns 10}
                     {:max-turns 100}
                     {:require-done-tool false}
                     {:require-done-tool true}]
         numeric-max-turns (->> ward-stack (keep :max-turns) (apply min))
         require-done (boolean (some :require-done-tool ward-stack))
         ;; Set up an agent that wants to echo many times but will be truncated at 2 turns
         llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:tool-calls [{:id "w1" :gate :echo :args {:text "Analyzing Q1 revenue: $3.7M"}}]}
                                             {:tool-calls [{:id "w2" :gate :echo :args {:text "Analyzing Q2 revenue: $4.0M"}}]}
                                             {:tool-calls [{:id "w3" :gate :done :args {:answer "Full analysis complete"}}]}]))
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You are a quarterly revenue analyst. Echo each quarter's data as you process it, then call done with a summary. You MUST call echo for every quarter before calling done."}
                  :circle {:medium :conversation
                           :gates [:done :echo]
                           :wards [{:max-turns 2}]}}
         ;; The agent wants to echo many times, but the ward cuts it off at 2 turns
         run (runtime/cast cantrip "Analyze revenue for Q1 through Q4. Echo each quarter, then summarize.")]
     ;; ── Narrative ──
     (println "=== Pattern 05: Ward Composition + Truncation ===")
     (println "Wards are safety boundaries that limit what the loop can do.")
     (println "When multiple wards stack, the strictest wins (WARD-1):\n")
     (println "Ward stack:" (pr-str ward-stack))
     (println "  Composed max-turns:" numeric-max-turns "(min of 50, 10, 100)")
     (println "  Composed require-done-tool:" require-done "(OR of false, true)\n")
     (println "Truncation demo — agent wants to echo Q1-Q4 but ward allows only 2 turns:")
     (println "  Status:" (:status run))
     (println "  Turns used:" (count (:turns run)))
     (println "\nThe agent never reached done. The ward stopped it. This is truncation, not failure.")
     {:pattern 5
      :composed {:max-turns numeric-max-turns
                 :require-done-tool require-done}
      :run run})))

;; ── Example 06: Medium ─────────────────────────────────────────────────────

(defn example-06-medium
  "Pattern 06: same gates, different medium; action space changes A = M U G - W (CIRCLE-11, MEDIUM-1, MEDIUM-2).
   Conversation medium uses tool-call messages; code medium writes and executes Clojure."
  ([] (example-06-medium {}))
  ([{:as opts :keys [conversation-llm-config code-llm-config]}]
   (let [gates [:done :echo]
         wards [{:max-turns 3}]
         conversation-circle {:medium :conversation :gates gates :wards wards}
         code-circle {:medium :code :gates gates :wards wards}
         ;; Compare the capability views — same gates, different action space
         conversation-view (medium/capability-view conversation-circle {})
         code-view (medium/capability-view code-circle {})
         ;; Conversation medium: LLM picks tools via structured tool_calls
         conv-llm (if conversation-llm-config
                    conversation-llm-config
                    (resolve-llm-config opts [{:tool-calls [{:id "m1" :gate :done :args {:answer "MRR growth is 14% QoQ, healthy for Series B stage"}}]}]))
         ;; Code medium: LLM writes Clojure that calls gates programmatically
         code-llm (if code-llm-config
                    code-llm-config
                    (resolve-llm-config opts [{:content "(submit-answer (str \"MRR: $\" (* 3.7 1.14) \"M after 14% growth\"))"}]))
         conversation-run (runtime/cast
                           {:llm conv-llm
                            :identity {:system-prompt "You are a SaaS metrics analyst. Use echo to log observations, then call done with your conclusion."}
                            :circle conversation-circle}
                           "What does 14% QoQ MRR growth mean for a Series B company? Call done with your answer.")
         code-run (runtime/cast
                   {:llm code-llm
                    :identity {:system-prompt "You write Clojure code to analyze SaaS metrics. Available functions: (submit-answer value) to return your final answer. Write a single Clojure expression."}
                    :circle (update code-circle :wards conj {:require-done-tool true})}
                   "Calculate post-growth MRR if base was $3.7M and growth is 14%. Submit the result.")]
     ;; ── Narrative ──
     (println "=== Pattern 06: Medium Comparison ===")
     (println "Same gates, different medium. The formula A = M U G - W means")
     (println "changing the medium changes the action space.\n")
     (println "Conversation medium:" (:medium conversation-view))
     (println "  LLM uses structured tool_calls to invoke gates")
     (println "  Status:" (get-in conversation-run [:status]))
     (println "  Result:" (get-in conversation-run [:result]))
     (println "\nCode medium:" (:medium code-view))
     (println "  LLM writes Clojure code that calls gates programmatically")
     (println "  Status:" (get-in code-run [:status]))
     (println "  Result:" (get-in code-run [:result]))
     (println "\nSame gates [:done :echo], but the medium determines HOW the LLM uses them.")
     {:pattern 6
      :conversation {:view conversation-view :run conversation-run}
      :code {:view code-view :run code-run}})))

;; ── Example 07: Full Agent ─────────────────────────────────────────────────

(defn example-07-full-agent
  "Pattern 07: code medium + real gates; error steers next turn and state accumulates (MEDIUM-2, LOOP-1, LOOP-3).
   The agent tries to read a file, gets an error, and recovers by trying a different approach."
  ([] (example-07-full-agent {}))
  ([{:as opts :keys [llm-config]}]
   (let [llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:content "(do (def first_try (call-gate :read-report {:path \"q4.md\"})) first_try)"}
                                             {:content "(do (def fallback (call-gate :read {:path \"q4.txt\"})) (submit-answer fallback))"}]))
         ;; Simulated workspace filesystem with quarterly revenue data
         filesystem {"/workspace/q4.txt" "Q4 Revenue: $4.8M | Churn: 3.1% | NRR: 118% | New logos: 47"}
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You write Clojure code to analyze SaaS data. Available functions:\n- (call-gate :read-report {:path \"filename\"}) - read a formatted report (may error)\n- (call-gate :read {:path \"filename\"}) - read a plain data file\n- (submit-answer value) - return your final answer\nIf a gate call errors, try a different approach. The file q4.txt exists in the workspace."}
                  :circle {:medium :code
                           :gates {:done {}
                                   :read-report {:dependencies {:root "/workspace"}
                                                 :result-behavior :throw
                                                 :error "ENOENT: q4.md not found — report format unavailable"}
                                   :read {:dependencies {:root "/workspace"}}}
                           :dependencies {:filesystem filesystem}
                           :wards [{:max-turns 4} {:require-done-tool true}]}}
         run (runtime/cast cantrip "Read the quarterly data file and return its contents. Try read-report first with q4.md, and if that fails, use read with q4.txt.")
         observations (mapcat :observation (:turns run))
         gate-seq (mapv :gate observations)
         error-count (count (filter :is-error observations))
         success-count (count (remove :is-error observations))]
     ;; ── Narrative ──
     (println "=== Pattern 07: Error Steering (Code Agent) ===")
     (println "A code-medium agent tries to read Q4 data. The first approach fails,")
     (println "and the error observation steers the LLM to recover on the next turn.\n")
     ;; Inspect actual turns — show what really happened, not a hardcoded story
     (doseq [[idx turn] (map-indexed vector (:turns run))]
       (let [obs (:observation turn)
             gates-this-turn (mapv :gate obs)
             errors? (seq (filter :is-error obs))]
         (println (str "  Turn " (inc idx) ": gates=" gates-this-turn
                       (when errors? " [errors observed]")))))
     (println "\nTotal turns:" (count (:turns run)))
     (println "Gate sequence:" gate-seq)
     (println "Errors:" error-count "| Successes:" success-count)
     (println "Status:" (:status run))
     (println "Result:" (:result run))
     (println "\nThis is the loop at work (LOOP-1): error -> observation -> next turn -> recovery.")
     {:pattern 7
      :run run
      :gate-seq gate-seq
      :observations observations})))

;; ── Example 08: Folding ────────────────────────────────────────────────────

(defn example-08-folding
  "Pattern 08: folding compresses old turns in context; loom still keeps full history (LOOM-5, LOOM-6, PROD-4).
   Multi-turn financial analysis where older context gets folded to stay within limits."
  ([] (example-08-folding {}))
  ([{:as opts :keys [llm-config]}]
   (let [invocations (atom [])
         llm-cfg (if llm-config
                   llm-config
                   (if (= :scripted (:mode opts))
                     {:provider :fake
                      :record-inputs true
                      :responses-by-invocation true
                      :invocations invocations
                      :responses [{:tool-calls [{:id "f1" :gate :done :args {:answer "Q1 revenue was $3.2M with 4.5% churn"}}]}
                                  {:tool-calls [{:id "f2" :gate :done :args {:answer "Q2 improved to $3.7M revenue, churn dropped to 3.8%"}}]}
                                  {:tool-calls [{:id "f3" :gate :done :args {:answer "Q3 hit $4.2M revenue with 3.1% churn — clear upward trend across all three quarters"}}]}]}
                     (resolve-llm-config opts nil)))
         entity (runtime/summon {:llm llm-cfg
                                 :identity {:system-prompt "You are a SaaS metrics analyst tracking quarterly performance. Call done with your analysis for each question. Build on previous context when available."}
                                 :circle {:medium :conversation
                                          :gates [:done]
                                          :wards [{:max-turns 2}]}
                                 :runtime {:folding {:max_turns_in_context 1}}})
         _ (runtime/send entity "Analyze Q1 metrics: Revenue $3.2M, churn 4.5%, NRR 105%. Call done with your analysis.")
         _ (runtime/send entity "Now analyze Q2: Revenue $3.7M, churn 3.8%, NRR 112%. Call done comparing to Q1.")
         _ (runtime/send entity "Finally Q3: Revenue $4.2M, churn 3.1%, NRR 118%. Call done with the overall trend.")
         state (runtime/entity-state entity)
         folding-markers (->> @invocations
                              (mapcat :messages)
                              (keep :content)
                              (filter #(and (string? %) (.contains ^String % "Folded"))))]
     ;; ── Narrative ──
     (println "=== Pattern 08: Folding (Context Compression) ===")
     (println "Three sends to the same entity, but max_turns_in_context is 1.")
     (println "Older turns get folded (compressed) so the LLM sees a summary, not the full history.\n")
     (println "Send 1: Q1 analysis (no folding yet, first turn)")
     (println "Send 2: Q2 analysis (Q1 turn gets folded into a summary)")
     (println "Send 3: Q3 analysis (Q1+Q2 folded, only Q2 turn visible in full)\n")
     (println "Folding markers observed:" (count folding-markers))
     (println "Total turns in loom:" (:turn-count state))
     (println "Identity preserved through folding (LOOM-6):"
              (some? (get-in state [:loom :identity :system-prompt])))
     (println "\nThe loom keeps ALL turns permanently (LOOM-5).")
     (println "Identity and gate definitions are never folded (LOOM-6).")
     (println "Folding only affects what the LLM sees in its context window (PROD-4).")
     (println "This is how long-running analysis stays within token limits.")
     {:pattern 8
      :state state
      :invocations @invocations
      :folding-markers (vec folding-markers)})))

;; ── Example 09: Composition ────────────────────────────────────────────────

(defn example-09-composition
  "Pattern 09: parent delegates to children; batch delegation runs multiple child casts (COMP-1, COMP-3, LOOM-8).
   A coordinator delegates to a revenue analyst and a risk analyst."
  ([] (example-09-composition {}))
  ([{:as opts :keys [llm-config]}]
  (let [parent-llm (if llm-config
                     llm-config
                     (resolve-llm-config opts [{:tool-calls [{:id "p1" :gate :done :args {:answer "Delegation complete: both analysts reported"}}]}]))
        child-conv-llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:tool-calls [{:id "c1" :gate :done :args {:answer "child-conversation"}}]}]))
        child-code-llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:content "(submit-answer \"child-code\")"}]))
        ;; Parent coordinator with depth ward to prevent infinite delegation
        parent (runtime/summon
                {:llm parent-llm
                 :identity {:system-prompt "You are a SaaS analysis coordinator. Delegate tasks to specialist analysts, then synthesize their findings. Call done with your summary."}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3} {:max-depth 3}]}})
        ;; Revenue analyst (conversation medium)
        child-conversation {:llm child-conv-llm
                            :identity {:system-prompt "You are a revenue analyst. Analyze the given metrics and call done with your findings."}
                            :circle {:medium :conversation
                                     :gates [:done]
                                     :wards [{:max-turns 2}]}}
        ;; Risk analyst (code medium — computes metrics programmatically)
        child-code {:llm child-code-llm
                    :identity {:system-prompt "You write Clojure code to analyze risk metrics. Use (submit-answer value) to return your analysis."}
                    :circle {:medium :code
                             :gates [:done]
                             :wards [{:max-turns 2} {:require-done-tool true}]}}
        ;; Single delegation: revenue analyst
        single (runtime/call-agent parent {:intent "Analyze Q3 revenue: $4.2M ARR, 62% from enterprise expansion. What's the growth trajectory?" :cantrip child-conversation})
        ;; Batch delegation: both analysts in parallel
        batch (runtime/call-agent-batch parent [{:intent "What drove the Q3 revenue increase? Focus on segment breakdown." :cantrip child-conversation}
                                                {:intent "Compute churn risk score: base_churn=3.1%, smb_weight=0.4, smb_churn=8.2%, enterprise_churn=1.1%" :cantrip child-code}])]
    ;; ── Narrative ──
    (println "=== Pattern 09: Composition (Parent-Child Delegation) ===")
    (println "A coordinator delegates to specialist analysts (COMP-1).")
    (println "Children run in their own circles with their own wards.\n")
    (println "Single delegation (revenue analyst):")
    (println "  Status:" (:status single))
    (println "  Result:" (:result single))
    (println "\nBatch delegation (revenue + risk analysts in parallel):")
    (println "  Statuses:" (mapv :status batch))
    (println "  Results:" (mapv :result batch))
    (println "\nParent loom records delegation as turns (LOOM-8).")
    (println "Depth ward prevents infinite delegation chains (COMP-3).")
    {:pattern 9
     :single single
     :batch batch
     :parent-state (runtime/entity-state parent)})))

;; ── Example 10: Loom ───────────────────────────────────────────────────────

(defn example-10-loom
  "Pattern 10: inspect loom as the key artifact after a run (LOOM-1, LOOM-3, LOOM-7).
   The loom records every turn: what the LLM said, what gates were called, what was observed.
   Shows both terminated and truncated runs to demonstrate LOOM-7."
  ([] (example-10-loom {}))
  ([{:as opts :keys [llm-config]}]
   (let [;; Run A: terminated — agent echoes then calls done within turn limit
         terminated-run (runtime/cast {:llm (if llm-config
                                              llm-config
                                              (resolve-llm-config opts [{:tool-calls [{:id "l1" :gate :echo :args {:text "Processing: MRR $4.2M, churn 3.1%, NRR 118%"}}]}
                                                                        {:tool-calls [{:id "l2" :gate :done :args {:answer "SaaS metrics are healthy: strong NRR indicates net expansion exceeds churn"}}]}]))
                                       :identity {:system-prompt "You are a SaaS metrics analyst. First echo your observations about the data, then call done with your conclusion."}
                                       :circle {:medium :conversation
                                                :gates [:done :echo]
                                                :wards [{:max-turns 4}]}}
                                      "Analyze these SaaS metrics: MRR $4.2M, churn 3.1%, NRR 118%. Echo your observations first, then call done with your conclusion.")
         ;; Run B: truncated — agent wants to echo many times but ward cuts it at 1 turn
         truncated-run (runtime/cast {:llm (resolve-llm-config {:mode :scripted}
                                                               [{:tool-calls [{:id "t1" :gate :echo :args {:text "Starting analysis..."}}]}])
                                      :identity {:system-prompt "Echo each metric individually before concluding."}
                                      :circle {:medium :conversation
                                               :gates [:done :echo]
                                               :wards [{:max-turns 1}]}}
                                     "Analyze all quarterly metrics one by one.")
         ;; Inspect the terminated run's loom
         turns (:turns terminated-run)
         loom-turns (get-in terminated-run [:loom :turns])
         terminated-count (count (filter :terminated loom-turns))
         truncated-count (count (filter :truncated loom-turns))
         token-usage (:cumulative-usage terminated-run)
         gate-calls (mapcat :observation turns)]
     ;; ── Narrative ──
     (println "=== Pattern 10: Loom Inspection ===")
     (println "The loom is the permanent record of everything that happened (LOOM-1).")
     (println "It captures turns, gate calls, observations, and token usage.\n")
     (println "--- Run A: Terminated (agent reached done) ---")
     (println "  Status:" (:status terminated-run))
     (println "  Result:" (:result terminated-run))
     (println "  Loom turns:" (count loom-turns))
     (println "  Gates called:" (mapv :gate gate-calls))
     (println "  Terminated turns:" terminated-count "| Truncated turns:" truncated-count)
     (println "  Token usage:" token-usage)
     (println "\n--- Run B: Truncated (ward stopped the loop before done) ---")
     (println "  Status:" (:status truncated-run))
     (println "  Result:" (:result truncated-run))
     (let [trunc-loom-turns (get-in truncated-run [:loom :turns])]
       (println "  Loom turns:" (count trunc-loom-turns))
       (println "  Last turn truncated?" (:truncated (last trunc-loom-turns))))
     (println "\nTerminated vs truncated (LOOM-7): the loom records which outcome occurred.")
     (println "The loom is append-only (LOOM-3). Once a turn is recorded, it cannot be modified.")
     (println "This is the audit trail for every decision the agent made.")
     {:pattern 10
      :status (:status terminated-run)
      :result (:result terminated-run)
      :turn-count (count turns)
      :loom-turn-count (count loom-turns)
      :terminated-count terminated-count
      :truncated-count truncated-count
      :token-usage token-usage
      :gates-called (mapv :gate gate-calls)
      :run terminated-run
      :truncated-run truncated-run})))

;; ── Example 11: Persistent Entity ──────────────────────────────────────────

(defn example-11-persistent-entity
  "Pattern 11: summon once, send twice; state accumulates across sends (ENTITY-5, ENTITY-6).
   A persistent entity gathers metrics on first send, then builds on them in the second."
  ([] (example-11-persistent-entity {}))
  ([{:as opts :keys [llm-config]}]
   (let [entity (runtime/summon
                 {:llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:tool-calls [{:id "s1" :gate :done :args {:answer "Q3 metrics gathered: MRR $4.2M, churn 3.1%, NRR 118%, 47 new logos"}}]}
                                                   {:tool-calls [{:id "s2" :gate :done :args {:answer "Based on Q3 data: projected Q4 MRR is $4.8M assuming 14% QoQ growth continues"}}]}]))
                  :identity {:system-prompt "You are a persistent SaaS analyst. You remember previous conversations. Call done with your analysis for each question."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 3}]}})
         ;; First send: gather the raw metrics
         first-send (runtime/send entity "Gather Q3 SaaS metrics: MRR $4.2M, churn 3.1%, NRR 118%, 47 new logos. Call done with a summary.")
         ;; Second send: build on the gathered data (entity remembers the first send)
         second-send (runtime/send entity "Based on the Q3 data you just gathered, project Q4 MRR assuming the growth trend continues. Call done with your projection.")
         state (runtime/entity-state entity)]
     ;; ── Narrative ──
     (println "=== Pattern 11: Persistent Entity ===")
     (println "Summon creates a long-lived entity. Each send adds to its history (ENTITY-5).\n")
     (println "Send 1 — Gather metrics:")
     (println "  Status:" (:status first-send))
     (println "  Result:" (:result first-send))
     (println "\nSend 2 — Build on previous data (entity remembers Send 1):")
     (println "  Status:" (:status second-send))
     (println "  Result:" (:result second-send))
     (println "\nAccumulated state:")
     (println "  Total turns:" (:turn-count state))
     (println "  Loom turns:" (count (get-in state [:loom :turns])))
     (println "\nThe entity's loom grew across both sends (ENTITY-6).")
     (println "Unlike cast (Pattern 04), sends share state within the same entity.")
     {:pattern 11
      :entity-id (:entity-id state)
      :first-send first-send
      :second-send second-send
      :state state})))

;; ── Example 12: Familiar ───────────────────────────────────────────────────

(defn example-12-familiar
  "Pattern 12: familiar delegates to child cantrips with different mediums/llms and keeps memory (COMP-7, LOOM-8, LOOM-12).
   A code-medium coordinator delegates to specialist children and combines their results."
  ([] (example-12-familiar {}))
  ([{:as opts :keys [llm-config]}]
   (let [parent-llm (if llm-config
                      llm-config
                      (resolve-llm-config opts [{:content "(do
  (def a (call-agent {:intent \"Analyze Q3 revenue drivers and list top 3\" :system-prompt \"You are a revenue analyst. Answer concisely. Call (submit-answer your-answer) when done.\"}))
  (def b (call-agent {:intent \"Compute weighted churn risk score from Q3 data\" :system-prompt \"You are a risk analyst. Answer concisely. Call (submit-answer your-answer) when done.\"}))
  (submit-answer (str \"Revenue drivers: \" a \"\\nChurn risk: \" b)))"}
                                     {:content "(submit-answer \"second familiar send\")"}]))
         ;; Children use their own FakeLLM in scripted mode, parent's LLM in real mode
         child-llm (when (= :scripted (:mode opts))
                     {:provider :fake
                      :responses [{:tool-calls [{:id "fc1" :gate :done :args {:answer "child-a-result"}}]}
                                  {:tool-calls [{:id "fc2" :gate :done :args {:answer "child-b-result"}}]}]})
         entity (runtime/summon
                 {:llm parent-llm
                  :identity {:system-prompt "You are a coordinator. Delegate work to children and combine results.\n\nONLY these functions exist:\n- (call-agent {:intent \"task\" :system-prompt \"child role\"}) — delegate to a child, returns answer string\n- (submit-answer value) — finish and return your combined answer\n\nRULES:\n- ALWAYS include :system-prompt in call-agent so children know their role.\n- Do NOT define functions, macros, or error handling. Just call-agent and submit-answer.\n- Keep intents short and specific.\n- You MUST call (submit-answer ...) in every response.\n\nExample:\n(def trends (call-agent {:intent \"List top 3 Q3 revenue trends\" :system-prompt \"You are a revenue analyst. Answer concisely. Call (submit-answer answer) when done.\"}))\n(def risks (call-agent {:intent \"List top 2 risks from Q3 data\" :system-prompt \"You are a risk analyst. Answer concisely. Call (submit-answer answer) when done.\"}))\n(submit-answer (str \"Trends: \" trends \"\\nRisks: \" risks))"}
                  :circle {:medium :code
                           :gates [:done]
                           :wards [{:max-turns 4} {:max-depth 2} {:require-done-tool true}]
                           :dependencies (when child-llm {:default-child-llm child-llm})}})
         ;; First send: delegate two analyses to children
         first-send (runtime/send entity "Delegate two analyses: (1) Q3 revenue drivers, (2) churn risk score. Combine their results.")
         ;; Second send: entity remembers the delegation from first send
         second-send (runtime/send entity "Submit a summary of the analyses you coordinated in the previous task.")
         state (runtime/entity-state entity)]
     ;; ── Narrative ──
     (println "=== Pattern 12: Familiar (Code Coordinator + Child Agents) ===")
     (println "A code-medium parent writes Clojure to construct child cantrips,")
     (println "delegate tasks, and combine results (COMP-7).\n")
     (println "Send 1 — Coordinate two child analysts:")
     (println "  Status:" (:status first-send))
     (println "  Result:" (:result first-send))
     (println "\nSend 2 — Entity remembers previous delegation:")
     (println "  Status:" (:status second-send))
     (println "  Result:" (:result second-send))
     (println "\nLoom turns:" (count (get-in state [:loom :turns])))
     (println "The parent's loom records child delegations as observations (LOOM-8).")
     (println "The familiar pattern: persistent entity + code medium + child delegation.")
     {:pattern 12
      :first-send first-send
      :second-send second-send
      :state state})))

;; ── Example 13: ACP ────────────────────────────────────────────────────────

(defn example-13-acp
  "Optional adapter pattern: ACP router on summon/send lifecycle (PROD-6, PROD-7).
   Wraps a cantrip in the Agent Communication Protocol for interop with external systems."
  ([] (example-13-acp {}))
  ([{:as opts :keys [llm-config]}]
   (let [cantrip {:llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:tool-calls [{:id "a1" :gate :done :args {:answer "Q3 executive summary: Revenue $4.2M (+14%), churn 3.1% (-2pp), NRR 118%"}}]}]))
                  :identity {:system-prompt "You are a SaaS metrics analyst accessible via ACP. Call done with your analysis."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 2}]}}
         ;; ACP lifecycle: initialize -> session/new -> session/prompt
         [router-1 _ _] (acp/handle-request (acp/new-router cantrip)
                                            {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
         [router-2 session-res _] (acp/handle-request router-1
                                                      {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
         session-id (get-in session-res [:result :sessionId])
         [_ prompt-res _] (acp/handle-request router-2
                                              {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                               :params {:sessionId session-id
                                                        :prompt "Generate Q3 executive summary with key SaaS metrics. Call done with the summary."}})]
     ;; ── Narrative ──
     (println "=== Pattern 13: ACP (Agent Communication Protocol) ===")
     (println "ACP wraps a cantrip in a JSON-RPC protocol for external access (PROD-6).\n")
     (println "Step 1: Initialize router (protocol handshake)")
     (println "Step 2: Create session (maps to summon)")
     (println "  Session ID:" session-id)
     (println "Step 3: Send prompt (maps to send)")
     (println "  Response:" (get-in prompt-res [:result :output]))
     (println "\nACP is an adapter, not a new concept. It maps to summon/send underneath.")
     (println "The cantrip, circle, and loom work identically whether accessed directly or via ACP.")
     {:pattern 13
      :session-id session-id
      :response prompt-res})))

;; ── Pattern Notes ──────────────────────────────────────────────────────────

(def pattern-notes
  {"01" {:fn #'example-01-llm-query :rules ["LLM-1" "LLM-3"]}
   "02" {:fn #'example-02-gate :rules ["CIRCLE-1" "LOOP-3" "LOOP-7"]}
   "03" {:fn #'example-03-circle :rules ["CIRCLE-1" "CIRCLE-2" "CANTRIP-1"]}
   "04" {:fn #'example-04-cantrip :rules ["CANTRIP-1" "CANTRIP-2" "INTENT-1"]}
   "05" {:fn #'example-05-wards :rules ["WARD-1" "CIRCLE-2"]}
   "06" {:fn #'example-06-medium :rules ["CIRCLE-11" "MEDIUM-1" "MEDIUM-2"]}
   "07" {:fn #'example-07-full-agent :rules ["MEDIUM-2" "LOOP-1" "LOOP-3"]}
   "08" {:fn #'example-08-folding :rules ["LOOM-5" "LOOM-6" "PROD-4"]}
   "09" {:fn #'example-09-composition :rules ["COMP-1" "COMP-3" "LOOM-8"]}
   "10" {:fn #'example-10-loom :rules ["LOOM-1" "LOOM-3" "LOOM-7"]}
   "11" {:fn #'example-11-persistent-entity :rules ["ENTITY-5" "ENTITY-6"]}
   "12" {:fn #'example-12-familiar :rules ["COMP-7" "LOOM-8" "LOOM-12"]}
   "13" {:fn #'example-13-acp :rules ["PROD-6" "PROD-7"]}})
