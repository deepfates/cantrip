(ns cantrip.llm-test
  (:require [clojure.test :refer [deftest is testing]]
            [cantrip.llm :as llm]))

(deftest llm-requires-content-or-tool-calls
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"neither content nor tool_calls"
                        (llm/query {:provider :fake
                                        :responses [{}]}
                                       {:turn-index 0
                                        :messages []
                                        :tools []
                                        :tool-choice :auto
                                        :previous-tool-call-ids []}))))

(deftest llm-requires-unique-tool-call-ids
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"duplicate tool call ID"
                        (llm/query {:provider :fake
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

(deftest llm-enforces-required-tool-choice
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"tool_choice required"
                        (llm/query {:provider :fake
                                        :responses [{:content "hello"}]}
                                       {:turn-index 0
                                        :messages []
                                        :tools []
                                        :tool-choice :required
                                        :previous-tool-call-ids []}))))

(deftest llm-enforces-tool-result-linkage
  (is (thrown-with-msg? clojure.lang.ExceptionInfo
                        #"without matching tool call"
                        (llm/query {:provider :fake
                                        :responses [{:content "step 1"}
                                                    {:content "step 2"
                                                     :tool-results [{:tool-call-id "call_99"
                                                                     :content "oops"}]}]}
                                       {:turn-index 1
                                        :messages []
                                        :tools []
                                        :tool-choice :auto
                                        :previous-tool-call-ids ["call_1"]}))))

(deftest llm-normalizes-tool-call-keys
  (let [resp (llm/query {:provider :fake
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

(deftest llm-can-record-query-inputs
  (let [invocations (atom [])
        _ (llm/query {:provider :fake
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

(deftest tool-description-is-serialized
  (let [tool {:name "echo" :description "Echo back the input" :parameters {"type" "object"}}
        result (#'cantrip.llm/tool->openai tool)]
    (is (= "Echo back the input"
           (get-in result ["function" "description"]))
        "Tool description must be included in serialized output")))

(deftest openai-model-required
  (is (thrown? clojure.lang.ExceptionInfo
               (#'cantrip.llm/openai-model {}))
      "Must throw when :model is not provided"))
