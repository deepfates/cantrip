(ns cantrip.examples
  (:require [cantrip.protocol.acp :as acp]
            [cantrip.runtime :as runtime]))

(defn example-01-crystal-gate-primitives
  "Pattern 01-02: minimal crystal + done gate loop."
  []
  (runtime/cast {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :done
                                                      :args {:answer "ok"}}]}]}
                 :call {:system-prompt "example-01"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 2}]}}
                "say ok"))

(defn example-07-conversation-medium
  "Pattern 07: conversation medium baseline."
  []
  (runtime/cast {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :done
                                                      :args {:answer "conversation"}}]}]}
                 :call {:system-prompt "example-07"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 2}]}}
                "run conversation"))

(defn example-08-code-medium
  "Pattern 08: code medium with submit-answer bridge."
  []
  (runtime/cast {:crystal {:provider :fake
                           :responses [{:content "(submit-answer \"code-ok\")"}]}
                 :call {:system-prompt "example-08"
                        :require-done-tool true}
                 :circle {:medium :code
                          :gates [:done]
                          :wards [{:max-turns 2}]}}
                "run code medium"))

(defn example-10-composition-batch
  "Pattern 10: parent entity composing child cantrips in batch."
  []
  (let [parent (runtime/invoke {:crystal {:provider :fake
                                          :responses [{:tool-calls [{:id "p1"
                                                                     :gate :done
                                                                     :args {:answer "parent"}}]}]}
                                :call {:system-prompt "example-10"}
                                :circle {:medium :conversation
                                         :gates [:done]
                                         :wards [{:max-turns 2} {:max-depth 2}]}})
        child (fn [answer]
                {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "c1"
                                                      :gate :done
                                                      :args {:answer answer}}]}]}
                 :call {:system-prompt "child"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 2}]}})]
    (runtime/call-agent-batch parent
                              [{:cantrip (child "a") :intent "child a"}
                               {:cantrip (child "b") :intent "child b"}])))

(defn example-11-folding
  "Pattern 11: folding policy compacts old turns in working context."
  []
  (let [invocations (atom [])
        entity (runtime/invoke
                {:crystal {:provider :fake
                           :record-inputs true
                           :responses-by-invocation true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "f1" :gate :done :args {:answer "1"}}]}
                                       {:tool-calls [{:id "f2" :gate :done :args {:answer "2"}}]}
                                       {:tool-calls [{:id "f3" :gate :done :args {:answer "3"}}]}]}
                 :call {:system-prompt "example-11"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3}]}
                 :runtime {:folding {:max_turns_in_context 1}}})]
    (runtime/cast-intent entity "one")
    (runtime/cast-intent entity "two")
    (runtime/cast-intent entity "three")
    {:invocations @invocations
     :state (runtime/entity-state entity)}))

(defn example-12-code-agent
  "Pattern 12: code-medium full loop using submit-answer."
  []
  (runtime/cast {:crystal {:provider :fake
                           :responses [{:content "(do (def x 1) (submit-answer (str \"x=\" x)))"}]}
                 :call {:system-prompt "example-12"
                        :require-done-tool true}
                 :circle {:medium :code
                          :gates [:done]
                          :wards [{:max-turns 3}]}}
                "run code agent"))

(defn example-13-acp-session
  "Pattern 13: ACP initialize + session/new + session/prompt."
  []
  (let [cantrip {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "a1"
                                                      :gate :done
                                                      :args {:answer "acp-ok"}}]}]}
                 :call {:system-prompt "example-13"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 2}]}}
        [r1 _ _] (acp/handle-request (acp/new-router cantrip)
                                     {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [r2 new-res _] (acp/handle-request r1
                                           {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
        sid (get-in new-res [:result :sessionId])
        [_ res _] (acp/handle-request r2
                                      {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                       :params {:sessionId sid :prompt "hello"}})]
    res))

(defn example-prod-2-retry
  "Production pattern: retryable provider failure recovered as one turn."
  []
  (let [invocations (atom [])]
    (runtime/cast {:crystal {:provider :fake
                             :record-inputs true
                             :invocations invocations
                             :responses-by-invocation true
                             :responses [{:error {:status 429 :message "rate limited"}}
                                         {:tool-calls [{:id "r1" :gate :done :args {:answer "retried"}}]}]}
                   :call {:system-prompt "retry"}
                   :circle {:medium :conversation
                            :gates [:done]
                            :wards [{:max-turns 3}]}
                   :retry {:max_retries 1
                           :retryable_status_codes [429]}}
                  "retry run")))
