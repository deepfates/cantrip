(ns cantrip.examples
  (:require [cantrip.runtime :as runtime]))

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
(ns cantrip.examples)