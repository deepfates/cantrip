(ns cantrip.crystal-test
  (:require [clojure.test :refer [deftest is testing]]
            [cantrip.crystal :as crystal]))

(deftest crystal-requires-content-or-tool-calls
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"neither content nor tool_calls"
                        (crystal/query {:provider :fake
                                        :responses [{}]}
                                       {:turn-index 0
                                        :messages []
                                        :tools []
                                        :tool-choice :auto
                                        :previous-tool-call-ids []}))))

(deftest crystal-requires-unique-tool-call-ids
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"duplicate tool call ID"
                        (crystal/query {:provider :fake
                                        :responses [{:tool-calls [{:id "call_1"
                                                                   :gate :echo
                                                                   :args {:text "a"}}
                                                                  {:id "call_1"
                                                                   :gate :echo
                                                                   :args {:text "b"}}]}]}
                                       {:turn-index 0
                                        :messages []
                                        :tools []
                                        :tool-choice :auto
                                        :previous-tool-call-ids []}))))

(deftest crystal-enforces-required-tool-choice
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"tool_choice required"
                        (crystal/query {:provider :fake
                                        :responses [{:content "hello"}]}
                                       {:turn-index 0
                                        :messages []
                                        :tools []
                                        :tool-choice :required
                                        :previous-tool-call-ids []}))))

(deftest crystal-enforces-tool-result-linkage
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"without matching tool call"
                        (crystal/query {:provider :fake
                                        :responses [{:content "step 1"}
                                                    {:content "step 2"
                                                     :tool-results [{:tool-call-id "call_99"
                                                                     :content "oops"}]}]}
                                       {:turn-index 1
                                        :messages []
                                        :tools []
                                        :tool-choice :auto
                                        :previous-tool-call-ids ["call_1"]}))))

(deftest crystal-normalizes-tool-call-keys
  (let [resp (crystal/query {:provider :fake
                             :responses [{:tool-calls [{:id "call_1"
                                                        :name :done
                                                        :arguments {:answer "ok"}}]}]}
                            {:turn-index 0
                             :messages []
                             :tools []
                             :tool-choice :auto
                             :previous-tool-call-ids []})]
    (is (= [{:id "call_1" :gate :done :args {:answer "ok"}}]
           (:tool-calls resp)))))

(deftest crystal-can-record-query-inputs
  (let [invocations (atom [])
        _ (crystal/query {:provider :fake
                          :record-inputs true
                          :invocations invocations
                          :responses [{:content "ok"}]}
                         {:turn-index 0
                          :messages [{:role :system :content "s"}]
                          :tools [{:name "done"}]
                          :tool-choice :auto
                          :previous-tool-call-ids []})]
    (is (= 1 (count @invocations)))
    (is (= :auto (-> @invocations first :tool-choice)))
    (is (= [{:name "done"}] (-> @invocations first :tools)))))
