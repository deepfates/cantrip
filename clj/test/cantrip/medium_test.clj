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
