(ns cantrip.acp-test
  (:require [clojure.test :refer [deftest is]]
            [cantrip.protocol.acp :as acp]))

(def acp-cantrip
  {:crystal {:provider :fake
             :responses [{:content "ok"}]}
   :call {:system-prompt "test"}
   :circle {:medium :conversation
            :gates [:done]
            :wards [{:max-turns 2}]}})

(deftest initialize-and-session-new
  (let [[r1 init-res _] (acp/handle-request (acp/new-router acp-cantrip)
                                            {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [_ new-res _] (acp/handle-request r1
                                          {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})]
    (is (true? (:initialized? r1)))
    (is (= "sess_1" (get-in new-res [:result :sessionId])))))

(deftest session-prompt-accepts-common-shapes
  (let [[r1 _ _] (acp/handle-request (acp/new-router acp-cantrip)
                                     {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [r2 new-res _] (acp/handle-request r1
                                           {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
        sid (get-in new-res [:result :sessionId])
        [_ res-a _] (acp/handle-request r2
                                        {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                         :params {:sessionId sid :prompt "hello"}})
        [_ res-b _] (acp/handle-request r2
                                        {:jsonrpc "2.0" :id "4" :method "session/prompt"
                                         :params {:sessionId sid :prompt {:content [{:type "text" :text "hello"}]}}})]
    (is (= "ok" (get-in res-a [:result :output 0 :text])))
    (is (= "ok" (get-in res-b [:result :output 0 :text])))))

(deftest session-continuity-preserves-history
  (let [[r1 _ _] (acp/handle-request (acp/new-router acp-cantrip)
                                     {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [r2 new-res _] (acp/handle-request r1
                                           {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
        sid (get-in new-res [:result :sessionId])
        [r3 _ _] (acp/handle-request r2
                                     {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                      :params {:sessionId sid :prompt "first"}})
        [r4 _ _] (acp/handle-request r3
                                     {:jsonrpc "2.0" :id "4" :method "session/prompt"
                                      :params {:sessionId sid :prompt "second"}})]
    (is (= ["first" "second"] (get-in r4 [:sessions sid :history])))))

(deftest acp-output-redacts-secrets
  (let [cantrip {:crystal {:provider :fake
                           :responses [{:content "token sk-proj-secret"}]}
                 :call {:system-prompt "test"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 2}]}}
        [r1 _ _] (acp/handle-request (acp/new-router cantrip)
                                     {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [r2 new-res _] (acp/handle-request r1
                                           {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
        sid (get-in new-res [:result :sessionId])
        [_ prompt-res updates] (acp/handle-request r2
                                                   {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                                    :params {:sessionId sid :prompt "hello"}})]
    (is (= "token [REDACTED]" (get-in prompt-res [:result :output 0 :text])))
    (is (= "token [REDACTED]" (get-in (first updates) [:params :text])))))

(deftest session-uses-persistent-invoked-entity
  (let [invocations (atom [])
        cantrip {:crystal {:provider :fake
                           :record-inputs true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :done
                                                      :args {:answer "ok"}}]}]}
                 :call {:system-prompt "test"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 2}]}}
        [r1 _ _] (acp/handle-request (acp/new-router cantrip)
                                     {:jsonrpc "2.0" :id "1" :method "initialize" :params {:protocolVersion 1}})
        [r2 new-res _] (acp/handle-request r1
                                           {:jsonrpc "2.0" :id "2" :method "session/new" :params {}})
        sid (get-in new-res [:result :sessionId])
        [r3 _ _] (acp/handle-request r2
                                     {:jsonrpc "2.0" :id "3" :method "session/prompt"
                                      :params {:sessionId sid :prompt "first"}})
        [_ _ _] (acp/handle-request r3
                                    {:jsonrpc "2.0" :id "4" :method "session/prompt"
                                     :params {:sessionId sid :prompt "second"}})]
    (is (= 2 (count @invocations)))
    (is (= 4 (count (-> @invocations second :messages))))))
