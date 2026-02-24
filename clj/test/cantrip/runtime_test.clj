(ns cantrip.runtime-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [cantrip.runtime :as runtime]))

(def valid-cantrip
  {:crystal {:provider :fake}
   :call {:system-prompt "test"}
   :circle {:medium :conversation
            :gates [:done]
            :wards [{:max-turns 2}]}})

(deftest invoke-returns-entity-handle
  (testing "invoke returns an entity map with id and status"
    (let [entity (runtime/invoke valid-cantrip)]
      (is (string? (:entity-id entity)))
      (is (= :ready (:status entity)))
      (is (instance? clojure.lang.IAtom (:loom entity)))
      (is (instance? clojure.lang.IAtom (:medium-state entity)))
      (is (instance? clojure.lang.IAtom (:cumulative-usage entity))))))

(deftest cast-terminates-on-successful-done
  (let [cantrip (assoc valid-cantrip
                       :crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "call_1"
                                                            :gate :done
                                                            :args {:answer "ok"}}]}]})
        result (runtime/cast cantrip "hello")]
    (is (= :terminated (:status result)))
    (is (= "ok" (:result result)))
    (is (= 1 (count (:turns result))))))

(deftest malformed-done-does-not-terminate
  (let [cantrip (assoc valid-cantrip
                       :crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "call_1"
                                                            :gate :done
                                                            :args {}}]}
                                             {:tool-calls [{:id "call_2"
                                                            :gate :done
                                                            :args {:answer "fixed"}}]}]})
        result (runtime/cast cantrip "hello")
        t1 (first (:turns result))]
    (is (= :terminated (:status result)))
    (is (= "fixed" (:result result)))
    (is (= 2 (count (:turns result))))
    (is (true? (-> t1 :observation first :is-error)))))

(deftest text-only-termination-default
  (let [cantrip (assoc valid-cantrip
                       :crystal {:provider :fake
                                 :responses [{:content "plain response"}]})
        result (runtime/cast cantrip "hello")]
    (is (= :terminated (:status result)))
    (is (= "plain response" (:result result)))
    (is (= 1 (count (:turns result))))))

(deftest text-only-continues-when-done-required
  (let [cantrip (-> valid-cantrip
                    (assoc :call {:system-prompt "test"
                                  :require-done-tool true})
                    (assoc :crystal {:provider :fake
                                     :responses [{:content "thinking"}
                                                 {:tool-calls [{:id "call_1"
                                                                :gate :done
                                                                :args {:answer "42"}}]}]}))
        result (runtime/cast cantrip "hello")]
    (is (= :terminated (:status result)))
    (is (= "42" (:result result)))
    (is (= 2 (count (:turns result))))))

(deftest truncates-when-max-turns-hit
  (let [cantrip (-> valid-cantrip
                    (assoc :call {:system-prompt "test"
                                  :require-done-tool true})
                    (assoc :crystal {:provider :fake
                                     :responses [{:content "a"}
                                                 {:content "b"}
                                                 {:content "c"}]}))
        result (runtime/cast cantrip "hello")]
    (is (= :truncated (:status result)))
    (is (nil? (:result result)))
    (is (= 2 (count (:turns result))))))

(deftest cast-builds-call-context-for-crystal
  (let [invocations (atom [])
        cantrip {:crystal {:provider :fake
                           :record-inputs true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :echo
                                                      :args {:text "1"}}]}
                                       {:tool-calls [{:id "call_2"
                                                      :gate :done
                                                      :args {:answer "ok"}}]}]}
                 :call {:system-prompt "You are a test agent"}
                 :circle {:medium :conversation
                          :gates [:done :echo]
                          :wards [{:max-turns 4}]}}
        _ (runtime/cast cantrip "test context")
        first-call (first @invocations)
        second-call (second @invocations)]
    (is (= {:role :system :content "You are a test agent"}
           (first (:messages first-call))))
    (is (= {:role :user :content "test context"}
           (second (:messages first-call))))
    (is (= 2 (count (:messages first-call))))
    (is (= 4 (count (:messages second-call))))))

(deftest cast-derives-tools-from-circle-gates
  (let [invocations (atom [])
        cantrip {:crystal {:provider :fake
                           :record-inputs true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :done
                                                      :args {:answer "ok"}}]}]}
                 :call {:system-prompt "test"}
                 :circle {:medium :conversation
                          :gates [{:name :done
                                   :parameters {:type "object"}}
                                  {:name :read
                                   :parameters {:type "object"}}]
                          :wards [{:max-turns 2}]}}]
    (runtime/cast cantrip "tool shape")
    (is (= ["done" "read"]
           (mapv :name (-> @invocations first :tools))))))

(deftest invoke-cast-intent-persists-turn-history
  (let [invocations (atom [])
        entity (runtime/invoke
                {:crystal {:provider :fake
                           :record-inputs true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :done
                                                      :args {:answer "ok"}}]}]}
                 :call {:system-prompt "test"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3}]}})
        first-result (runtime/cast-intent entity "a")
        second-result (runtime/cast-intent entity "b")
        state (runtime/entity-state entity)]
    (is (= "ok" (:result first-result)))
    (is (= "ok" (:result second-result)))
    (is (= 2 (:turn-count state)))
    (is (map? (:medium-state state)))
    (is (= 2 (count (get-in state [:loom :turns]))))
    (is (= 2 (count @invocations)))
    (is (= 4 (count (-> @invocations second :messages))))))

(deftest cast-tracks-usage-and-turn-metadata
  (let [cantrip {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "call_1"
                                                      :gate :echo
                                                      :args {:text "1"}}]
                                        :usage {:prompt_tokens 100
                                                :completion_tokens 50}}
                                       {:tool-calls [{:id "call_2"
                                                      :gate :done
                                                      :args {:answer "ok"}}]
                                        :usage {:prompt_tokens 200
                                                :completion_tokens 30}}]}
                 :call {:system-prompt "usage test"}
                 :circle {:medium :conversation
                          :gates [:done :echo]
                          :wards [{:max-turns 4}]}}
        result (runtime/cast cantrip "track usage")
        first-turn (first (:turns result))
        second-turn (second (:turns result))]
    (is (= {:prompt_tokens 300 :completion_tokens 80}
           (:cumulative-usage result)))
    (is (number? (get-in first-turn [:metadata :duration_ms])))
    (is (number? (get-in first-turn [:metadata :timestamp])))
    (is (= 100 (get-in first-turn [:metadata :tokens_prompt])))
    (is (= 50 (get-in first-turn [:metadata :tokens_completion])))
    (is (= 200 (get-in second-turn [:metadata :tokens_prompt])))
    (is (= 30 (get-in second-turn [:metadata :tokens_completion])))))

(deftest cast-retries-retryable-provider-errors-in-single-turn
  (let [invocations (atom [])
        cantrip {:crystal {:provider :fake
                           :record-inputs true
                           :responses-by-invocation true
                           :invocations invocations
                           :responses [{:error {:status 429 :message "rate limited"}}
                                       {:tool-calls [{:id "call_1"
                                                      :gate :done
                                                      :args {:answer "ok"}}]}]}
                 :call {:system-prompt "retry test"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3}]}
                 :retry {:max_retries 1
                         :retryable_status_codes [429]}}
        result (runtime/cast cantrip "retry intent")]
    (is (= :terminated (:status result)))
    (is (= "ok" (:result result)))
    (is (= 1 (count (:turns result))))
    (is (= 2 (count @invocations)))))

(deftest folding-limits-context-with-summary-message
  (let [invocations (atom [])
        entity (runtime/invoke
                {:crystal {:provider :fake
                           :record-inputs true
                           :responses-by-invocation true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "call_1" :gate :done :args {:answer "a"}}]}
                                       {:tool-calls [{:id "call_2" :gate :done :args {:answer "b"}}]}
                                       {:tool-calls [{:id "call_3" :gate :done :args {:answer "c"}}]}]}
                 :call {:system-prompt "fold test"}
                 :circle {:medium :conversation
                          :gates [:done]
                          :wards [{:max-turns 3}]}
                 :runtime {:folding {:max_turns_in_context 1}}})]
    (runtime/cast-intent entity "one")
    (runtime/cast-intent entity "two")
    (runtime/cast-intent entity "three")
    (is (= 3 (count @invocations)))
    (is (some #(and (= :system (:role %))
                    (str/includes? (:content %) "Folded"))
              (-> @invocations (nth 2) :messages)))))

(deftest ephemeral-observations-compact-older-turn-messages
  (let [invocations (atom [])
        cantrip {:crystal {:provider :fake
                           :record-inputs true
                           :invocations invocations
                           :responses [{:tool-calls [{:id "call_1" :gate :echo :args {:text "one"}}]}
                                       {:tool-calls [{:id "call_2" :gate :echo :args {:text "two"}}]}
                                       {:tool-calls [{:id "call_3" :gate :done :args {:answer "ok"}}]}]}
                 :call {:system-prompt "ephemeral test"
                        :require-done-tool true}
                 :circle {:medium :conversation
                          :gates [:done :echo]
                          :wards [{:max-turns 5}]}
                 :runtime {:ephemeral-observations true}}
        result (runtime/cast cantrip "compact")
        third-messages (-> @invocations (nth 2) :messages)
        tool-contents (map :content (filter #(= :tool (:role %)) third-messages))
        first-turn-observation (-> result :turns first :observation first :result)]
    (is (some #(str/starts-with? % "[ephemeral-ref:") tool-contents))
    (is (= "gate not implemented" first-turn-observation))))
