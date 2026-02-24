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
(ns cantrip.examples-test)