(ns cantrip.examples-test
  (:require [cantrip.examples :as examples]
            [clojure.test :refer [deftest is]]))

(deftest example-01-runs
  (is (= "ok" (:result (examples/example-01-crystal-gate-primitives)))))

(deftest example-02-runs
  (is (= "ok" (:result (examples/example-02-gate-primitives)))))

(deftest example-03-runs
  (is (map? (examples/example-03-circle-invariants))))

(deftest example-04-runs
  (is (= "fixed" (:result (examples/example-04-loop-termination-semantics)))))

(deftest example-05-runs
  (is (= :terminated (:status (examples/example-05-ward-composition)))))

(deftest example-06-runs
  (is (= "portable" (:result (examples/example-06-provider-portability)))))

(deftest example-07-runs
  (is (= "conversation" (:result (examples/example-07-conversation-medium)))))

(deftest example-08-runs
  (is (= "code-ok" (:result (examples/example-08-code-medium)))))

(deftest example-09-runs
  (let [view (examples/example-09-medium-capability-view)]
    (is (= :conversation (get-in view [:conversation :medium])))
    (is (= :code (get-in view [:code :medium])))))

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

(deftest example-14-runs
  (is (= :terminated (:status (examples/example-14-recursive-delegation)))))

(deftest example-prod-2-runs
  (let [res (examples/example-prod-2-retry)]
    (is (= :terminated (:status res)))
    (is (= "retried" (:result res)))
    (is (= 1 (count (:turns res))))))

(deftest pattern-notes-cover-01-14
  (is (= (set (map #(format "%02d" %) (range 1 15)))
         (set (keys examples/pattern-notes)))))
(ns cantrip.examples-test)
