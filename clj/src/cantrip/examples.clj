(ns cantrip.examples
  (:refer-clojure :exclude [send])
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]
            [cantrip.llm :as llm]
            [cantrip.medium :as medium]
            [cantrip.protocol.acp :as acp]
            [cantrip.runtime :as runtime]))

(defn example-01-llm-query
  "Pattern 01: one raw LLM query. Stateless round-trip only."
  ([] (example-01-llm-query {}))
  ([{:keys [llm-config]}]
   (let [llm-cfg (or llm-config
                     {:provider :fake
                      :responses [{:content "Q4 revenue is up 18% YoY."}]})
         query {:turn-index 0
                :messages [{:role :user
                            :content "Summarize the quarterly revenue trend in one sentence."}]
                :tools []
                :tool-choice :none
                :previous-tool-call-ids []}
         response (llm/query llm-cfg query)]
     (println "01 LLM query response:" (:content response))
     {:llm llm-cfg
      :query query
      :response response})))

(defn example-02-gate
  "Pattern 02: gates are callable functions with metadata; done is special."
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
    {:tools tools
     :echo-exec echo-exec
     :done-exec done-exec
     :malformed-done malformed-done}))

(defn example-03-circle
  "Pattern 03: circle construction and invariant failures (CIRCLE-1, CIRCLE-2)."
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
    {:valid valid
     :missing-done missing-done
     :missing-wards missing-wards}))

(defn example-04-cantrip
  "Pattern 04: cantrip = llm + identity + circle; each cast is independent."
  ([] (example-04-cantrip {}))
  ([{:keys [llm-config]}]
   (let [llm-cfg (or llm-config
                     {:provider :fake
                      :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "north region leads"}}]}
                                  {:tool-calls [{:id "c2" :gate :done :args {:answer "services segment lags"}}]}]})
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "You are an analyst. Use done with the final summary."}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 3}]}}
         first-run (runtime/cast cantrip "Analyze retail category growth by region.")
         second-run (runtime/cast cantrip "Analyze product category churn by segment.")]
     (println "04 cast statuses:" (:status first-run) (:status second-run))
     {:cantrip cantrip
      :first-run first-run
      :second-run second-run
      :independent-entity-ids (not= (:entity-id first-run) (:entity-id second-run))})))

(defn example-05-wards
  "Pattern 05: ward composition law (min for numeric, OR for boolean) + truncation."
  ([] (example-05-wards {}))
  ([{:keys [llm-config]}]
   (let [ward-stack [{:max-turns 50}
                     {:max-turns 10}
                     {:max-turns 100}
                     {:require-done-tool false}
                     {:require-done-tool true}]
         numeric-max-turns (->> ward-stack (keep :max-turns) (apply min))
         require-done (boolean (some :require-done-tool ward-stack))
         llm-cfg (or llm-config
                     {:provider :fake
                      :responses [{:tool-calls [{:id "w1" :gate :echo :args {:text "turn 1"}}]}
                                  {:tool-calls [{:id "w2" :gate :echo :args {:text "turn 2"}}]}
                                  {:tool-calls [{:id "w3" :gate :done :args {:answer "late done"}}]}]})
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "Demonstrate truncation"}
                  :circle {:medium :conversation
                           :gates [:done :echo]
                           :wards [{:max-turns 2}]}}
         run (runtime/cast cantrip "Try to plan three steps, then finish.")]
     (println "05 composed max-turns:" numeric-max-turns "require-done-tool:" require-done)
     {:composed {:max-turns numeric-max-turns
                 :require-done-tool require-done}
      :run run})))

(defn example-06-medium
  "Pattern 06: same gates, different medium; action space changes (A = M ∪ G − W)."
  ([] (example-06-medium {}))
  ([{:keys [conversation-llm-config code-llm-config]}]
   (let [gates [:done :echo]
         wards [{:max-turns 3}]
         conversation-circle {:medium :conversation :gates gates :wards wards}
         code-circle {:medium :code :gates gates :wards wards}
         conversation-view (medium/capability-view conversation-circle {})
         code-view (medium/capability-view code-circle {})
         conversation-run (runtime/cast
                           {:llm (or conversation-llm-config
                                     {:provider :fake
                                      :responses [{:tool-calls [{:id "m1" :gate :done :args {:answer "conversation solved"}}]}]})
                            :identity {:system-prompt "Conversation medium only."}
                            :circle conversation-circle}
                           "Find the highest growth segment and finish.")
         code-run (runtime/cast
                   {:llm (or code-llm-config
                             {:provider :fake
                              :responses [{:content "(do (def trend \"upward\") (submit-answer trend))"}]})
                    :identity {:system-prompt "Code medium. Use submit-answer."
                               :require-done-tool true}
                    :circle code-circle}
                   "Compute a trend label from context and finish.")]
     (println "06 mediums:" (:medium conversation-view) "vs" (:medium code-view))
     {:conversation {:view conversation-view :run conversation-run}
      :code {:view code-view :run code-run}})))

(defn example-07-full-agent
  "Pattern 07: code medium + real gates; error steers next turn and state accumulates."
  ([] (example-07-full-agent {}))
  ([{:keys [llm-config]}]
   (let [llm-cfg (or llm-config
                     {:provider :fake
                      :responses [{:content "(do (def first_try (call-gate :read-report {:path \"q4.md\"})) first_try)"}
                                  {:content "(do (def fallback (call-gate :read {:path \"q4.txt\"})) (submit-answer fallback))"}]})
         filesystem {"/workspace/q4.txt" "Revenue +18%, margin +2.1pp"}
         cantrip {:llm llm-cfg
                  :identity {:system-prompt "Coding agent: recover from errors and finish with submit-answer."
                             :require-done-tool true}
                  :circle {:medium :code
                           :gates {:done {}
                                   :read-report {:dependencies {:root "/workspace"}
                                                 :result-behavior :throw
                                                 :error "ENOENT: q4.md missing"}
                                   :read {:dependencies {:root "/workspace"}}}
                           :dependencies {:filesystem filesystem}
                           :wards [{:max-turns 4}]}}
         run (runtime/cast cantrip "Read quarterly file and summarize trend.")
         observations (mapcat :observation (:turns run))
         gate-seq (mapv :gate observations)]
     (println "07 full agent turns:" (count (:turns run)))
     {:run run
      :gate-seq gate-seq
      :observations observations})))

(defn example-08-folding
  "Pattern 08: folding compresses old turns in context; loom still keeps full history."
  ([] (example-08-folding {}))
  ([{:keys [llm-config]}]
   (let [invocations (atom [])
         llm-cfg (or llm-config
                     {:provider :fake
                      :record-inputs true
                      :responses-by-invocation true
                      :invocations invocations
                      :responses [{:tool-calls [{:id "f1" :gate :done :args {:answer "first"}}]}
                                  {:tool-calls [{:id "f2" :gate :done :args {:answer "second"}}]}
                                  {:tool-calls [{:id "f3" :gate :done :args {:answer "third"}}]}]})
         entity (runtime/summon {:llm llm-cfg
                                 :identity {:system-prompt "Folding demo identity"}
                                 :circle {:medium :conversation
                                          :gates [:done]
                                          :wards [{:max-turns 2}]}
                                 :runtime {:folding {:max_turns_in_context 1}}})
         _ (runtime/send entity "Intent one: summarize revenue")
         _ (runtime/send entity "Intent two: summarize costs")
         _ (runtime/send entity "Intent three: summarize outlook")
         state (runtime/entity-state entity)
         folding-markers (->> @invocations
                              (mapcat :messages)
                              (keep :content)
                              (filter #(and (string? %) (.contains ^String % "Folded"))))]
     (println "08 folding markers observed:" (count folding-markers))
     {:state state
      :invocations @invocations
      :folding-markers (vec folding-markers)})))

(defn example-09-composition
  "Pattern 09: parent delegates to children; batch delegation runs multiple child casts."
  []
  (let [parent (runtime/summon
                {:llm {:provider :fake
                       :responses [{:tool-calls [{:id "p1" :gate :done :args {:answer "parent ready"}}]}]}
                 :identity {:system-prompt "Parent coordinator"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3} {:max-depth 3}]}})
        child-conversation {:llm {:provider :fake
                                  :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child-conversation"}}]}]}
                            :identity {:system-prompt "Child conversation identity"}
                            :circle {:medium :conversation
                                     :gates [:done]
                                     :wards [{:max-turns 2}]}}
        child-code {:llm {:provider :fake
                          :responses [{:content "(submit-answer \"child-code\")"}]}
                    :identity {:system-prompt "Child code identity"
                               :require-done-tool true}
                    :circle {:medium :code
                             :gates [:done]
                             :wards [{:max-turns 2}]}}
        single (runtime/call-agent parent {:intent "Analyze revenue bucket" :cantrip child-conversation})
        batch (runtime/call-agent-batch parent [{:intent "Analyze costs" :cantrip child-conversation}
                                                {:intent "Analyze outlook" :cantrip child-code}])]
    (println "09 composition child statuses:" (:status single) (mapv :status batch))
    {:single single
     :batch batch
     :parent-state (runtime/entity-state parent)}))

(defn example-10-loom
  "Pattern 10: inspect loom as the key artifact after a run."
  ([] (example-10-loom {}))
  ([{:keys [llm-config]}]
   (let [run (runtime/cast {:llm (or llm-config
                                     {:provider :fake
                                      :responses [{:tool-calls [{:id "l1" :gate :echo :args {:text "step 1"}}]}
                                                  {:tool-calls [{:id "l2" :gate :done :args {:answer "loom complete"}}]}]})
                            :identity {:system-prompt "Inspect loom metadata"}
                            :circle {:medium :conversation
                                     :gates [:done :echo]
                                     :wards [{:max-turns 4}]}}
                           "Analyze each category and summarize the overall trend.")
         turns (:turns run)
         loom-turns (get-in run [:loom :turns])
         terminated-count (count (filter :terminated loom-turns))
         truncated-count (count (filter :truncated loom-turns))
         token-usage (:cumulative-usage run)
         gate-calls (mapcat :observation turns)]
     (println "10 loom turns:" (count loom-turns))
     {:status (:status run)
      :result (:result run)
      :turn-count (count turns)
      :loom-turn-count (count loom-turns)
      :terminated-count terminated-count
      :truncated-count truncated-count
      :token-usage token-usage
      :gates-called (mapv :gate gate-calls)
      :run run})))

(defn example-11-persistent-entity
  "Pattern 11: summon once, send twice; state accumulates across sends."
  ([] (example-11-persistent-entity {}))
  ([{:keys [llm-config]}]
   (let [entity (runtime/summon
                 {:llm (or llm-config
                           {:provider :fake
                            :responses [{:tool-calls [{:id "s1" :gate :done :args {:answer "first cast complete"}}]}
                                        {:tool-calls [{:id "s2" :gate :done :args {:answer "second cast complete"}}]}]})
                  :identity {:system-prompt "Persistent analyst"}
                  :circle {:medium :conversation
                           :gates [:done]
                           :wards [{:max-turns 3}]}})
         first-send (runtime/send entity "Intent 1: analyze Q1 anomalies")
         second-send (runtime/send entity "Intent 2: compare Q1 vs Q2 anomalies")
         state (runtime/entity-state entity)]
     (println "11 persistent turn-count:" (:turn-count state))
     {:entity-id (:entity-id state)
      :first-send first-send
      :second-send second-send
      :state state})))

(defn example-12-familiar
  "Pattern 12: familiar delegates to child cantrips with different mediums/llms and keeps memory."
  ([] (example-12-familiar {}))
  ([{:keys [llm-config]}]
   (let [parent-llm (or llm-config
                        {:provider :fake
                         :responses [{:content "(do
  (def convo-child {:llm {:provider :fake
                          :responses [{:tool-calls [{:id \"fc1\" :gate :done :args {:answer \"conversation-child\"}}]}]}
                     :identity {:system-prompt \"Conversation child\"}
                     :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}})
  (def code-child {:llm {:provider :fake
                         :responses [{:content \"(submit-answer \\\"code-child\\\")\"}]}
                   :identity {:system-prompt \"Code child\" :require-done-tool true}
                   :circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}})
  (def a (call-agent {:intent \"child-one\" :cantrip convo-child}))
  (def b (call-agent {:intent \"child-two\" :cantrip code-child}))
  (submit-answer (str a \" + \" b)))"}
                                     {:content "(submit-answer \"second familiar send\")"}]})
         entity (runtime/summon
                 {:llm parent-llm
                  :identity {:system-prompt "You are a familiar: coordinate child cantrips in code."
                             :require-done-tool true}
                  :circle {:medium :code
                           :gates [:done]
                           :wards [{:max-turns 6} {:max-depth 4}]}})
         first-send (runtime/send entity "Build children to analyze revenue and cost trends.")
         second-send (runtime/send entity "Recall prior work and provide an updated summary.")
         state (runtime/entity-state entity)]
     (println "12 familiar loom turns:" (count (get-in state [:loom :turns])))
     {:first-send first-send
      :second-send second-send
      :state state})))

(defn example-13-acp
  "Optional adapter pattern: ACP router on summon/send lifecycle."
  []
  (let [cantrip {:llm {:provider :fake
                       :responses [{:tool-calls [{:id "a1" :gate :done :args {:answer "acp-result"}}]}]}
                 :identity {:system-prompt "ACP demo"}
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
                                                       :prompt "Analyze regional trend and respond."}})]
    {:session-id session-id
     :response prompt-res}))

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
