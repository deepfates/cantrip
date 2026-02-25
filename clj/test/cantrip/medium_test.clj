(ns cantrip.medium-test
  (:require [clojure.test :refer [deftest is]]
            [cantrip.medium :as medium]))

(deftest capability-view-dispatch
  (is (= :conversation
         (:medium (medium/capability-view {:medium :conversation :gates {:done {}}}
                                          {}))))
  (is (= :code
         (:medium (medium/capability-view {:medium :code :gates {:done {}}}
                                          {}))))
  (is (= :minecraft
         (:medium (medium/capability-view {:medium :minecraft :gates {:done {}}}
                                          {})))))

(deftest capability-view-normalizes-sequential-gates
  (let [view (medium/capability-view {:medium :conversation
                                      :gates [:done "echo" {:name :read}]}
                                     {})]
    (is (= ["done" "echo" "read"] (:gates view)))))

(deftest execute-utterance-dispatch
  (let [circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}
        utterance {:tool-calls [{:id "call_1" :gate :done :args {:answer "ok"}}]}
        result (medium/execute-utterance circle utterance {})]
    (is (true? (:terminated? result)))
    (is (= "ok" (:result result)))))

(deftest medium-state-hooks-dispatch
  (let [circle {:medium :conversation :gates [:done]}]
    (is (= {} (medium/snapshot-state circle {})))
    (is (= {:x 1} (medium/restore-state circle {:x 1} {})))))

(deftest code-medium-bridges-submit-answer-form
  (let [circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(submit-answer \"done\")"}
        result (medium/execute-utterance circle utterance {})]
    (is (true? (:terminated? result)))
    (is (= "done" (:result result)))))

(deftest code-medium-bridges-submit-underscore-form
  (let [circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(submit_answer \"done\")"}
        result (medium/execute-utterance circle utterance {})]
    (is (true? (:terminated? result)))
    (is (= "done" (:result result)))))

(deftest code-medium-reports-execution-errors
  (let [circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(unknown_fn 1)"}
        result (medium/execute-utterance circle utterance {})]
    (is (false? (:terminated? result)))
    (is (true? (-> result :observation first :is-error)))))

(deftest code-medium-supports-host-call-agent-bindings
  (let [circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(submit-answer (call-agent {:intent \"child\"}))"}
        deps {:call-agent-fn (fn [_] "child-ok")}
        result (medium/execute-utterance circle utterance deps)]
    (is (true? (:terminated? result)))
    (is (= "child-ok" (:result result)))))

(deftest code-medium-supports-host-call-agent-batch-bindings
  (let [circle {:medium :code :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(let [xs (call-agent-batch [{:intent \"a\"} {:intent \"b\"}])] (submit-answer (str (first xs) \",\" (second xs))))"}
        deps {:call-agent-batch-fn (fn [_] ["a" "b"])}
        result (medium/execute-utterance circle utterance deps)]
    (is (true? (:terminated? result)))
    (is (= "a,b" (:result result)))))

(deftest minecraft-medium-readonly-bindings
  (let [circle {:medium :minecraft :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(submit-answer (str (player) \"@\" (xyz)))"}
        deps {:player-fn (fn [] "Alex")
              :xyz-fn (fn [] [1 2 3])}
        result (medium/execute-utterance circle utterance deps)]
    (is (true? (:terminated? result)))
    (is (= "Alex@[1 2 3]" (:result result)))))

(deftest minecraft-medium-mutation-guard
  (let [circle {:medium :minecraft :gates [:done] :wards [{:max-turns 2}]}
        utterance {:content "(do (set-block [0 64 0] :stone) (submit-answer \"ok\"))"}
        deps {:set-block-fn (fn [_ _] :ok)
              :allow-mutation? false}
        result (medium/execute-utterance circle utterance deps)]
    (is (false? (:terminated? result)))
    (is (true? (-> result :observation first :is-error)))))
