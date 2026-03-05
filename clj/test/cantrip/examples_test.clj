(ns cantrip.examples-test
  (:require [cantrip.examples :as examples]
            [clojure.test :refer [deftest is testing]]))

(deftest example-01-llm-query-test
  (let [{:keys [response query]} (examples/example-01-llm-query)]
    (is (string? (:content response)))
    (is (= 1 (count (:messages query))))))

(deftest example-02-gate-test
  (let [{:keys [tools echo-exec done-exec malformed-done]} (examples/example-02-gate)]
    (is (seq tools))
    (is (= false (get-in echo-exec [:observation 0 :is-error])))
    (is (= true (:terminated? done-exec)))
    (is (= false (:terminated? malformed-done)))
    (is (= true (get-in malformed-done [:observation 0 :is-error])))))

(deftest example-03-circle-test
  (let [{:keys [valid missing-done missing-wards]} (examples/example-03-circle)]
    (is (map? valid))
    (is (= "CIRCLE-1" (:rule missing-done)))
    (is (= "CIRCLE-2" (:rule missing-wards)))))

(deftest example-04-cantrip-test
  (let [{:keys [first-run second-run independent-entity-ids]} (examples/example-04-cantrip)]
    (is (= :terminated (:status first-run)))
    (is (= :terminated (:status second-run)))
    (is (pos? (count (:turns first-run))))
    (is (true? independent-entity-ids))))

(deftest example-05-wards-test
  (let [{:keys [composed run]} (examples/example-05-wards)]
    (is (= 10 (:max-turns composed)))
    (is (true? (:require-done-tool composed)))
    (is (= :truncated (:status run)))
    (is (pos? (count (:turns run))))))

(deftest example-06-medium-test
  (let [{:keys [conversation code]} (examples/example-06-medium)]
    (is (= :conversation (get-in conversation [:view :medium])))
    (is (= :code (get-in code [:view :medium])))
    (is (= :terminated (get-in conversation [:run :status])))
    (is (= :terminated (get-in code [:run :status])))))

(deftest example-07-full-agent-test
  (let [{:keys [run observations gate-seq]} (examples/example-07-full-agent)]
    (is (= :terminated (:status run)))
    (is (>= (count (:turns run)) 2))
    (is (some :is-error observations))
    (is (some #(= "done" %) gate-seq))))

(deftest example-08-folding-test
  (let [{:keys [state invocations folding-markers]} (examples/example-08-folding)]
    (is (= 3 (count invocations)))
    (is (= 3 (:turn-count state)))
    (is (seq folding-markers))
    (is (= "Folding demo identity" (get-in state [:loom :identity :system-prompt])))))

(deftest example-09-composition-test
  (let [{:keys [single batch parent-state]} (examples/example-09-composition)]
    (is (= :terminated (:status single)))
    (is (= 2 (count batch)))
    (is (every? #(= :terminated (:status %)) batch))
    (is (>= (count (get-in parent-state [:loom :turns])) 3))))

(deftest example-10-loom-test
  (let [{:keys [status turn-count loom-turn-count terminated-count truncated-count token-usage gates-called]} (examples/example-10-loom)]
    (is (= :terminated status))
    (is (pos? turn-count))
    (is (= turn-count loom-turn-count))
    (is (= 1 terminated-count))
    (is (= 0 truncated-count))
    (is (map? token-usage))
    (is (seq gates-called))))

(deftest example-11-persistent-entity-test
  (let [{:keys [first-send second-send state]} (examples/example-11-persistent-entity)]
    (is (= :terminated (:status first-send)))
    (is (= :terminated (:status second-send)))
    (is (= 2 (:turn-count state)))
    (is (= 2 (count (get-in state [:loom :turns]))))))

(deftest example-12-familiar-test
  (let [{:keys [first-send second-send state]} (examples/example-12-familiar)]
    (is (= :terminated (:status first-send)))
    (is (= :terminated (:status second-send)))
    (is (>= (:turn-count state) 2))
    (is (seq (get-in state [:loom :turns])))))

(deftest example-13-acp-test
  (let [{:keys [session-id response]} (examples/example-13-acp)]
    (is (string? session-id))
    (is (= "2.0" (:jsonrpc response)))
    (is (seq (get-in response [:result :output])))))

(deftest pattern-notes-coverage-test
  (is (= (set (map #(format "%02d" %) (range 1 14)))
         (set (keys examples/pattern-notes)))))
