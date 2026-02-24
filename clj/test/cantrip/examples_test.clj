(ns cantrip.examples-test
  (:require [cantrip.examples :as examples]
            [clojure.test :refer [deftest is]]))

(deftest example-01-runs
  (is (= "ok" (:result (examples/example-01-crystal-gate-primitives)))))

(deftest example-07-runs
  (is (= "conversation" (:result (examples/example-07-conversation-medium)))))

(deftest example-08-runs
  (is (= "code-ok" (:result (examples/example-08-code-medium)))))

(deftest example-10-runs
  (let [results (examples/example-10-composition-batch)]
    (is (= ["a" "b"] (mapv :result results)))))

(deftest example-11-runs
  (let [{:keys [invocations state]} (examples/example-11-folding)]
    (is (= 3 (count invocations)))
    (is (= 3 (:turn-count state)))))

(deftest example-12-runs
  (is (= "x=1" (:result (examples/example-12-code-agent)))))

(deftest example-13-runs
  (is (= "acp-ok" (get-in (examples/example-13-acp-session) [:result :output 0 :text]))))

(deftest example-prod-2-runs
  (let [res (examples/example-prod-2-retry)]
    (is (= :terminated (:status res)))
    (is (= "retried" (:result res)))
    (is (= 1 (count (:turns res))))))
(ns cantrip.examples-test)
