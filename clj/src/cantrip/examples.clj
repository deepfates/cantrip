(ns cantrip.examples
  (:refer-clojure :exclude [send])
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]
            [cantrip.llm :as llm]
            [cantrip.medium :as medium]
            [cantrip.protocol.acp :as acp]
            [cantrip.runtime :as runtime]))

(defn- resolve-llm-config
  "Resolve LLM config. :scripted mode uses :fake provider.
   Default mode reads env vars and raises if missing."
  [opts scripted-responses]
  (if (= :scripted (:mode opts))
    {:provider :fake :responses scripted-responses}
    (let [model (or (System/getenv "OPENAI_MODEL")
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
      {:provider :openai
       :model model
       :api-key api-key
       :base-url base-url})))

(defn example-01-llm-query
  "Pattern 01: one raw LLM query. Stateless round-trip only (LLM-1, LLM-3)."
  ([] (example-01-llm-query {}))
  ([{:as opts :keys [llm-config]}]
   (let [llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:content "56"}]))
         query {:turn-index 0
                :messages [{:role :user
                            :content "What is 7 multiplied by 8? Reply with just the number."}]
                :tools []
                :tool-choice :none
                :previous-tool-call-ids []}
         response (llm/query llm-cfg query)]
     (println "01 LLM query response:" (:content response))
     {:pattern 1
      :llm llm-cfg
      :query query
      :response response})))

(defn example-02-gate
  "Pattern 02: gates are callable functions with metadata; done is special (CIRCLE-1, LOOP-3, LOOP-7)."
  []
  (let [gate-list [{:name :echo
                    :parameters {:type "object"
                                 :properties {:text {:type "string"}}
                                 :required ["text"]}}
                   :done]
        tools (gates/gate-tools gate-list)
        circle-cfg {:medium :conversation
                    :gates gate-list
                    :wards [{:max-turns 3}]}
        echo-exec (circle/execute-tool-calls
                   circle-cfg
                   [{:id "call_1" :gate :echo :args {:text "hello from gate"}}])
        done-exec (circle/execute-tool-calls
                   circle-cfg
                   [{:id "call_2" :gate :done :args {:answer "finished"}}
                    {:id "call_3" :gate :echo :args {:text "should not run"}}])
        malformed-done (circle/execute-tool-calls
                        circle-cfg
                        [{:id "call_4" :gate :done :args {}}])]
    (println "02 gate tools:" (mapv :name tools))
    {:pattern 2
     :tools tools
     :echo-exec echo-exec
     :done-exec done-exec
     :malformed-done malformed-done}))

(defn example-03-circle
  "Pattern 03: circle construction and invariant failures (CIRCLE-1, CIRCLE-2, CANTRIP-1)."
  []
  (let [valid-cantrip {:llm {:provider :fake :responses []}
                       :identity {:system-prompt "Circle validator"}
                       :circle {:medium :conversation
                                :gates [:done :echo]
                                :wards [{:max-turns 2}]}}
        valid (runtime/new-cantrip valid-cantrip)
        missing-done (try
                       (runtime/new-cantrip
                        {:llm {:provider :fake}
                         :identity {:system-prompt "invalid"}
                         :circle {:medium :conversation
                                  :gates [:echo]
                                  :wards [{:max-turns 2}]}})
                       (catch clojure.lang.ExceptionInfo e
                         {:message (.getMessage e)
                          :rule (:rule (ex-data e))}))
        missing-wards (try
                        (runtime/new-cantrip
                         {:llm {:provider :fake}
                          :identity {:system-prompt "invalid"}
                          :circle {:medium :conversation
                                   :gates [:done]
                                   :wards []}})
                        (catch clojure.lang.ExceptionInfo e
                          {:message (.getMessage e)
                           :rule (:rule (ex-data e))}))]
    (println "03 circle valid gates:" (get-in valid [:circle :gates]))
    {:pattern 3
     :valid valid
     :missing-done missing-done
     :missing-wards missing-wards}))

(defn example-04-cantrip
  "Pattern 04: cantrip = llm + identity + circle; each cast is independent (CANTRIP-1, CANTRIP-2, INTENT-1)."
  ([] (example-04-cantrip {}))
  ([{:as opts :keys [llm-config]}]
   (let [llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:tool-calls [{:id "c1" :gate :done :args {:answer "north region leads"}}]}
                                             {:tool-calls [{:id "c2" :gate :done :args {:answer "services segment lags"}}]}]))
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You are a helpful assistant. You have one gate: done. Call the done gate with your answer when ready."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 3}]}}
         first-run (runtime/cast cantrip "What is the capital of France? Answer in one word.")
         second-run (runtime/cast cantrip "What is the capital of Japan? Answer in one word.")]
     (println "04 cast statuses:" (:status first-run) (:status second-run))
     {:pattern 4
      :cantrip cantrip
      :first-run first-run
      :second-run second-run
      :independent-entity-ids (not= (:entity-id first-run) (:entity-id second-run))})))

(defn example-05-wards
  "Pattern 05: ward composition law (min for numeric, OR for boolean) + truncation (WARD-1, CIRCLE-2)."
  ([] (example-05-wards {}))
  ([{:as opts :keys [llm-config]}]
   (let [ward-stack [{:max-turns 50}
                     {:max-turns 10}
                     {:max-turns 100}
                     {:require-done-tool false}
                     {:require-done-tool true}]
         numeric-max-turns (->> ward-stack (keep :max-turns) (apply min))
         require-done (boolean (some :require-done-tool ward-stack))
         llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:tool-calls [{:id "w1" :gate :echo :args {:text "turn 1"}}]}
                                             {:tool-calls [{:id "w2" :gate :echo :args {:text "turn 2"}}]}
                                             {:tool-calls [{:id "w3" :gate :done :args {:answer "late done"}}]}]))
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You have two gates: echo and done. You MUST call the echo gate on every turn. Do NOT call done until you have echoed at least 5 times. Call echo with a text argument each turn."}
                  :circle {:medium :conversation
                           :gates [:done :echo]
                           :wards [{:max-turns 2}]}}
         run (runtime/cast cantrip "Echo the numbers 1 through 10, one per turn, then call done.")]
     (println "05 composed max-turns:" numeric-max-turns "require-done-tool:" require-done)
     {:pattern 5
      :composed {:max-turns numeric-max-turns
                 :require-done-tool require-done}
      :run run})))

(defn example-06-medium
  "Pattern 06: same gates, different medium; action space changes A = M ∪ G − W (CIRCLE-12, MEDIUM-1, MEDIUM-2)."
  ([] (example-06-medium {}))
  ([{:as opts :keys [conversation-llm-config code-llm-config]}]
   (let [gates [:done :echo]
         wards [{:max-turns 3}]
         conversation-circle {:medium :conversation :gates gates :wards wards}
         code-circle {:medium :code :gates gates :wards wards}
         conversation-view (medium/capability-view conversation-circle {})
         code-view (medium/capability-view code-circle {})
         conv-llm (if conversation-llm-config
                    conversation-llm-config
                    (resolve-llm-config opts [{:tool-calls [{:id "m1" :gate :done :args {:answer "conversation solved"}}]}]))
         code-llm (if code-llm-config
                    code-llm-config
                    (resolve-llm-config opts [{:content "(do (def trend \"upward\") (submit-answer trend))"}]))
         conversation-run (runtime/cast
                           {:llm conv-llm
                            :identity {:system-prompt "You have two gates: echo and done. Call done with your answer when ready."}
                            :circle conversation-circle}
                           "What is 2 + 2? Call done with the answer.")
         code-run (runtime/cast
                   {:llm code-llm
                    :identity {:system-prompt "You write Clojure code. Available functions: (submit-answer value) to return your final answer. Write a single Clojure expression."
                               :require-done-tool true}
                    :circle code-circle}
                   "Compute (+ 3 4) and submit the result using (submit-answer result).")]
     (println "06 mediums:" (:medium conversation-view) "vs" (:medium code-view))
     {:pattern 6
      :conversation {:view conversation-view :run conversation-run}
      :code {:view code-view :run code-run}})))

(defn example-07-full-agent
  "Pattern 07: code medium + real gates; error steers next turn and state accumulates (MEDIUM-2, LOOP-1, LOOP-3)."
  ([] (example-07-full-agent {}))
  ([{:as opts :keys [llm-config]}]
   (let [llm-cfg (if llm-config
                   llm-config
                   (resolve-llm-config opts [{:content "(do (def first_try (call-gate :read-report {:path \"q4.md\"})) first_try)"}
                                             {:content "(do (def fallback (call-gate :read {:path \"q4.txt\"})) (submit-answer fallback))"}]))
         filesystem {"/workspace/q4.txt" "Revenue +18%, margin +2.1pp"}
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You write Clojure code. Available functions:\n- (call-gate :read-report {:path \"filename\"}) - read a report file (may error)\n- (call-gate :read {:path \"filename\"}) - read a plain file\n- (submit-answer value) - return your final answer\nIf a gate call errors, try a different approach. The file q4.txt exists in the workspace."
                             :require-done-tool true}
                  :circle {:medium :code
                           :gates {:done {}
                                   :read-report {:dependencies {:root "/workspace"}
                                                 :result-behavior :throw
                                                 :error "ENOENT: q4.md missing"}
                                   :read {:dependencies {:root "/workspace"}}}
                           :dependencies {:filesystem filesystem}
                           :wards [{:max-turns 4}]}}
         run (runtime/cast cantrip "Read the quarterly data file and return its contents. Try read-report first with q4.md, and if that fails, use read with q4.txt.")
         observations (mapcat :observation (:turns run))
         gate-seq (mapv :gate observations)]
     (println "07 full agent turns:" (count (:turns run)))
     {:pattern 7
      :run run
      :gate-seq gate-seq
      :observations observations})))

(defn example-08-folding
  "Pattern 08: folding compresses old turns in context; loom still keeps full history (LOOM-5, LOOM-6, PROD-4)."
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
                      :responses [{:tool-calls [{:id "f1" :gate :done :args {:answer "first"}}]}
                                  {:tool-calls [{:id "f2" :gate :done :args {:answer "second"}}]}
                                  {:tool-calls [{:id "f3" :gate :done :args {:answer "third"}}]}]}
                     (resolve-llm-config opts nil)))
         entity (runtime/summon {:llm llm-cfg
                                 :identity {:system-prompt "You have one gate: done. Call done with your answer for each question."}
                                 :circle {:medium :conversation
                                          :gates [:done]
                                          :wards [{:max-turns 2}]}
                                 :runtime {:folding {:max_turns_in_context 1}}})
         _ (runtime/send entity "What is 1 + 1? Call done with the answer.")
         _ (runtime/send entity "What is 2 + 2? Call done with the answer.")
         _ (runtime/send entity "What is 3 + 3? Call done with the answer.")
         state (runtime/entity-state entity)
         folding-markers (->> @invocations
                              (mapcat :messages)
                              (keep :content)
                              (filter #(and (string? %) (.contains ^String % "Folded"))))]
     (println "08 folding markers observed:" (count folding-markers))
     {:pattern 8
      :state state
      :invocations @invocations
      :folding-markers (vec folding-markers)})))

(defn example-09-composition
  "Pattern 09: parent delegates to children; batch delegation runs multiple child casts (COMP-1, COMP-3, LOOM-8)."
  ([] (example-09-composition {}))
  ([{:as opts :keys [llm-config]}]
  (let [parent-llm (if llm-config
                     llm-config
                     (resolve-llm-config opts [{:tool-calls [{:id "p1" :gate :done :args {:answer "parent ready"}}]}]))
        child-conv-llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:tool-calls [{:id "c1" :gate :done :args {:answer "child-conversation"}}]}]))
        child-code-llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:content "(submit-answer \"child-code\")"}]))
        parent (runtime/summon
                {:llm parent-llm
                 :identity {:system-prompt "You have one gate: done. Call done with your answer."}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3} {:max-depth 3}]}})
        child-conversation {:llm child-conv-llm
                            :identity {:system-prompt "You have one gate: done. Call done with your answer."}
                            :circle {:medium :conversation
                                     :gates [:done]
                                     :wards [{:max-turns 2}]}}
        child-code {:llm child-code-llm
                    :identity {:system-prompt "You write Clojure code. Use (submit-answer value) to return your answer."
                               :require-done-tool true}
                    :circle {:medium :code
                             :gates [:done]
                             :wards [{:max-turns 2}]}}
        single (runtime/call-agent parent {:intent "What is 5 + 3? Answer with just the number." :cantrip child-conversation})
        batch (runtime/call-agent-batch parent [{:intent "What is 10 - 4? Answer with just the number." :cantrip child-conversation}
                                                {:intent "Compute (+ 7 8) and submit the result." :cantrip child-code}])]
    (println "09 composition child statuses:" (:status single) (mapv :status batch))
    {:pattern 9
     :single single
     :batch batch
     :parent-state (runtime/entity-state parent)})))

(defn example-10-loom
  "Pattern 10: inspect loom as the key artifact after a run (LOOM-1, LOOM-3, LOOM-7)."
  ([] (example-10-loom {}))
  ([{:as opts :keys [llm-config]}]
   (let [run (runtime/cast {:llm (if llm-config
                                   llm-config
                                   (resolve-llm-config opts [{:tool-calls [{:id "l1" :gate :echo :args {:text "step 1"}}]}
                                                             {:tool-calls [{:id "l2" :gate :done :args {:answer "loom complete"}}]}]))
                            :identity {:system-prompt "You have two gates: echo and done. First call echo with some text, then call done with your final answer."}
                            :circle {:medium :conversation
                                     :gates [:done :echo]
                                     :wards [{:max-turns 4}]}}
                           "Call echo with 'hello' first, then call done with 'finished'.")
         turns (:turns run)
         loom-turns (get-in run [:loom :turns])
         terminated-count (count (filter :terminated loom-turns))
         truncated-count (count (filter :truncated loom-turns))
         token-usage (:cumulative-usage run)
         gate-calls (mapcat :observation turns)]
     (println "10 loom turns:" (count loom-turns))
     {:pattern 10
      :status (:status run)
      :result (:result run)
      :turn-count (count turns)
      :loom-turn-count (count loom-turns)
      :terminated-count terminated-count
      :truncated-count truncated-count
      :token-usage token-usage
      :gates-called (mapv :gate gate-calls)
      :run run})))

(defn example-11-persistent-entity
  "Pattern 11: summon once, send twice; state accumulates across sends (ENTITY-5, ENTITY-6)."
  ([] (example-11-persistent-entity {}))
  ([{:as opts :keys [llm-config]}]
   (let [entity (runtime/summon
                 {:llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:tool-calls [{:id "s1" :gate :done :args {:answer "first cast complete"}}]}
                                                   {:tool-calls [{:id "s2" :gate :done :args {:answer "second cast complete"}}]}]))
                  :identity {:system-prompt "You have one gate: done. Call done with your answer for each question."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 3}]}})
         first-send (runtime/send entity "What is the square root of 144? Call done with the answer.")
         second-send (runtime/send entity "What is the square root of 256? Call done with the answer.")
         state (runtime/entity-state entity)]
     (println "11 persistent turn-count:" (:turn-count state))
     {:pattern 11
      :entity-id (:entity-id state)
      :first-send first-send
      :second-send second-send
      :state state})))

(defn example-12-familiar
  "Pattern 12: familiar delegates to child cantrips with different mediums/llms and keeps memory (COMP-7, LOOM-8, LOOM-12)."
  ([] (example-12-familiar {}))
  ([{:as opts :keys [llm-config]}]
   (let [parent-llm (if llm-config
                      llm-config
                      (resolve-llm-config opts [{:content "(do
  (def convo-child {:llm {:provider :fake
                          :responses [{:tool-calls [{:id \"fc1\" :gate :done :args {:answer \"child-a-result\"}}]}]}
                     :identity {:system-prompt \"Child agent. Call done with your answer.\"}
                     :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}})
  (def code-child {:llm {:provider :fake
                         :responses [{:content \"(submit-answer \\\"child-b-result\\\")\"}]}
                   :identity {:system-prompt \"Child code agent.\" :require-done-tool true}
                   :circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}})
  (def a (call-agent {:intent \"What is 10+20?\" :cantrip convo-child}))
  (def b (call-agent {:intent \"What is 30+40?\" :cantrip code-child}))
  (submit-answer (str \"Results: \" a \" and \" b)))"}
                                     {:content "(submit-answer \"second familiar send\")"}]))
         entity (runtime/summon
                 {:llm parent-llm
                  :identity {:system-prompt "You write Clojure code. Available functions:\n- (call-agent {:intent \"task\" :cantrip cantrip-map}) - delegate a task to a child agent, returns the child's answer as a string\n- (call-agent-batch [{:intent \"task1\" :cantrip c1} {:intent \"task2\" :cantrip c2}]) - delegate multiple tasks, returns a vector of answers\n- (submit-answer value) - return your final answer\nA cantrip map has keys :llm, :identity, :circle. Write Clojure code to construct child cantrips, delegate work, and combine results."
                             :require-done-tool true}
                  :circle {:medium :code
                           :gates [:done]
                           :wards [{:max-turns 6} {:max-depth 4}]}})
         first-send (runtime/send entity "Delegate two questions to child agents: 'What is 10+20?' and 'What is 30+40?'. Construct child cantrips and combine their answers.")
         second-send (runtime/send entity "Submit a summary of what you did in the previous task.")
         state (runtime/entity-state entity)]
     (println "12 familiar loom turns:" (count (get-in state [:loom :turns])))
     {:pattern 12
      :first-send first-send
      :second-send second-send
      :state state})))

(defn example-13-acp
  "Optional adapter pattern: ACP router on summon/send lifecycle (PROD-6, PROD-7)."
  ([] (example-13-acp {}))
  ([{:as opts :keys [llm-config]}]
   (let [cantrip {:llm (if llm-config
                         llm-config
                         (resolve-llm-config opts [{:tool-calls [{:id "a1" :gate :done :args {:answer "acp-result"}}]}]))
                  :identity {:system-prompt "You have one gate: done. Call done with your answer."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 2}]}}
        [router-1 _ _] (acp/handle-request (acp/new-router cantrip)
                                           {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [router-2 session-res _] (acp/handle-request router-1
                                                     {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
        session-id (get-in session-res [:result :sessionId])
        [_ prompt-res _] (acp/handle-request router-2
                                             {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                              :params {:sessionId session-id
                                                       :prompt "What is 3 + 3? Call done with the answer."}})]
    {:pattern 13
     :session-id session-id
     :response prompt-res})))

(def pattern-notes
  {"01" {:fn #'example-01-llm-query :rules ["LLM-1" "LLM-3"]}
   "02" {:fn #'example-02-gate :rules ["CIRCLE-1" "LOOP-3" "LOOP-7"]}
   "03" {:fn #'example-03-circle :rules ["CIRCLE-1" "CIRCLE-2" "CANTRIP-1"]}
   "04" {:fn #'example-04-cantrip :rules ["CANTRIP-1" "CANTRIP-2" "INTENT-1"]}
   "05" {:fn #'example-05-wards :rules ["WARD-1" "CIRCLE-2"]}
   "06" {:fn #'example-06-medium :rules ["CIRCLE-12" "MEDIUM-1" "MEDIUM-2"]}
   "07" {:fn #'example-07-full-agent :rules ["MEDIUM-2" "LOOP-1" "LOOP-3"]}
   "08" {:fn #'example-08-folding :rules ["LOOM-5" "LOOM-6" "PROD-4"]}
   "09" {:fn #'example-09-composition :rules ["COMP-1" "COMP-3" "LOOM-8"]}
   "10" {:fn #'example-10-loom :rules ["LOOM-1" "LOOM-3" "LOOM-7"]}
   "11" {:fn #'example-11-persistent-entity :rules ["ENTITY-5" "ENTITY-6"]}
   "12" {:fn #'example-12-familiar :rules ["COMP-7" "LOOM-8" "LOOM-12"]}
   "13" {:fn #'example-13-acp :rules ["PROD-6" "PROD-7"]}})
