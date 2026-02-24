(ns cantrip.crystal-test
  (:require [clojure.test :refer [deftest is testing]]
            [cantrip.crystal :as crystal]))

(deftest crystal-requires-content-or-tool-calls
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"neither content nor tool_calls"
                        (crystal/query {:provider :fake
                                        :responses [{}]}
                                       0
                                       {:tool-choice :auto
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
                                       0
                                       {:tool-choice :auto
                                        :previous-tool-call-ids []}))))

(deftest crystal-enforces-required-tool-choice
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"tool_choice required"
                        (crystal/query {:provider :fake
                                        :responses [{:content "hello"}]}
                                       0
                                       {:tool-choice :required
                                        :previous-tool-call-ids []}))))

(deftest crystal-enforces-tool-result-linkage
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"without matching tool call"
                        (crystal/query {:provider :fake
                                        :responses [{:content "step 1"}
                                                    {:content "step 2"
                                                     :tool-results [{:tool-call-id "call_99"
                                                                     :content "oops"}]}]}
                                       1
                                       {:tool-choice :auto
                                        :previous-tool-call-ids ["call_1"]}))))

(deftest crystal-normalizes-tool-call-keys
  (let [resp (crystal/query {:provider :fake
                             :responses [{:tool-calls [{:id "call_1"
                                                        :name :done
                                                        :arguments {:answer "ok"}}]}]}
                            0
                            {:tool-choice :auto
                             :previous-tool-call-ids []})]
    (is (= [{:id "call_1" :gate :done :args {:answer "ok"}}]
           (:tool-calls resp)))))
