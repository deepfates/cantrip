(ns cantrip.openai-test
  (:require [clojure.test :refer [deftest is testing]]
            [cantrip.crystal :as crystal]))

;; ---------------------------------------------------------------------------
;; Unit tests (always run, no API key needed)
;; ---------------------------------------------------------------------------

(deftest openai-provider-requires-api-key
  (testing "throws when no API key is configured"
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"API key is required"
         (crystal/query {:provider :openai
                         :model "gpt-4o-mini"
                         :api-key nil}
                        {:turn-index 0
                         :messages [{:role :user :content "hello"}]
                         :tools []
                         :tool-choice :auto
                         :previous-tool-call-ids []})))))

(deftest openai-unknown-provider-throws
  (testing "throws on unknown provider keyword"
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"unknown crystal provider"
         (crystal/query {:provider :llama-local}
                        {:turn-index 0
                         :messages [{:role :user :content "hi"}]
                         :tools []
                         :tool-choice :auto
                         :previous-tool-call-ids []})))))

(deftest fake-provider-still-works
  (testing "existing fake provider is not broken"
    (let [resp (crystal/query {:provider :fake
                               :responses [{:content "hello from fake"}]}
                              {:turn-index 0
                               :messages []
                               :tools []
                               :tool-choice :auto
                               :previous-tool-call-ids []})]
      (is (= "hello from fake" (:content resp))))))

;; ---------------------------------------------------------------------------
;; Integration test -- only runs when OPENAI_API_KEY env var is set
;; ---------------------------------------------------------------------------

(deftest ^:integration openai-simple-completion
  (let [api-key (System/getenv "OPENAI_API_KEY")]
    (when (and api-key (pos? (count api-key)))
      (testing "can make a real completion request"
        (let [resp (crystal/query {:provider :openai
                                   :model "gpt-4o-mini"
                                   :api-key api-key}
                                  {:turn-index 0
                                   :messages [{:role :system :content "Reply with exactly: PONG"}
                                              {:role :user :content "PING"}]
                                   :tools []
                                   :tool-choice :auto
                                   :previous-tool-call-ids []})]
          (is (string? (:content resp)))
          (is (pos? (get-in resp [:usage :prompt_tokens])))
          (is (pos? (get-in resp [:usage :completion_tokens]))))))))

(deftest ^:integration openai-tool-calling
  (let [api-key (System/getenv "OPENAI_API_KEY")]
    (when (and api-key (pos? (count api-key)))
      (testing "can invoke tools via OpenAI function calling"
        (let [resp (crystal/query {:provider :openai
                                   :model "gpt-4o-mini"
                                   :api-key api-key}
                                  {:turn-index 0
                                   :messages [{:role :system :content "You must call the done tool with {\"answer\": \"42\"}."}
                                              {:role :user :content "What is the answer?"}]
                                   :tools [{:name "done"
                                            :parameters {"type" "object"
                                                         "properties" {"answer" {"type" "string"}}
                                                         "required" ["answer"]}}]
                                   :tool-choice :required
                                   :previous-tool-call-ids []})]
          (is (seq (:tool-calls resp)))
          (is (string? (:id (first (:tool-calls resp)))))
          (is (= "done" (:gate (first (:tool-calls resp))))))))))
