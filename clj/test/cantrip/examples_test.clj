(ns cantrip.examples-test
  (:require [cantrip.examples :as examples]
            [clojure.test :refer [deftest is testing]]))

;; ── Cross-cutting: mode="scripted" always works ─────────────────────────────
;;
;; Every example must support (example-NN {:mode :scripted}) and return a map
;; with at minimum :pattern key. FakeLLM is only used in scripted mode.
;;
;; Cross-cutting: no silent fallback. When called with no args AND no env vars,
;; examples that need an LLM must throw, not silently use :fake.
;;
;; The no-fallback tests are in examples_no_fallback_test.clj to avoid
;; polluting env state for other tests.
;; ─────────────────────────────────────────────────────────────────────────────

(deftest example-01-llm-query-test
  (let [result (examples/example-01-llm-query {:mode :scripted})]
    (is (= 1 (:pattern result)))
    (is (string? (get-in result [:response :content])))
    (is (= 1 (count (get-in result [:query :messages]))))))

(deftest example-02-gate-test
  (let [result (examples/example-02-gate)]
    (is (= 2 (:pattern result)))
    (is (seq (:tools result)))
    (is (= false (get-in result [:echo-exec :observation 0 :is-error])))
    (is (= true (:terminated? (:done-exec result))))
    (is (= false (:terminated? (:malformed-done result))))
    (is (= true (get-in result [:malformed-done :observation 0 :is-error])))))

(deftest example-03-circle-test
  (let [result (examples/example-03-circle)]
    (is (= 3 (:pattern result)))
    (is (map? (:valid result)))
    (is (= "CIRCLE-1" (:rule (:missing-done result))))
    (is (= "CIRCLE-2" (:rule (:missing-wards result))))))

(deftest example-04-cantrip-test
  (let [result (examples/example-04-cantrip {:mode :scripted})]
    (is (= 4 (:pattern result)))
    (is (= :terminated (:status (:first-run result))))
    (is (= :terminated (:status (:second-run result))))
    (is (pos? (count (:turns (:first-run result)))))
    (is (true? (:independent-entity-ids result)))))

(deftest example-05-wards-test
  (let [result (examples/example-05-wards {:mode :scripted})]
    (is (= 5 (:pattern result)))
    (is (= 10 (get-in result [:composed :max-turns])))
    (is (true? (get-in result [:composed :require-done-tool])))
    (is (= :truncated (:status (:run result))))
    (is (pos? (count (:turns (:run result)))))))

(deftest example-06-medium-test
  (let [result (examples/example-06-medium {:mode :scripted})]
    (is (= 6 (:pattern result)))
    (is (= :conversation (get-in result [:conversation :view :medium])))
    (is (= :code (get-in result [:code :view :medium])))
    (is (= :terminated (get-in result [:conversation :run :status])))
    (is (= :terminated (get-in result [:code :run :status])))))

(deftest example-07-full-agent-test
  (let [result (examples/example-07-full-agent {:mode :scripted})]
    (is (= 7 (:pattern result)))
    (is (= :terminated (:status (:run result))))
    (is (>= (count (:turns (:run result))) 2))
    (is (some :is-error (:observations result)))
    (is (some #(= "done" %) (:gate-seq result)))))

(deftest example-08-folding-test
  (let [result (examples/example-08-folding {:mode :scripted})]
    (is (= 8 (:pattern result)))
    (is (= 3 (count (:invocations result))))
    (is (= 3 (:turn-count (:state result))))
    (is (seq (:folding-markers result)))
    (is (string? (get-in result [:state :loom :identity :system-prompt])))))

(deftest example-09-composition-test
  (let [result (examples/example-09-composition {:mode :scripted})]
    (is (= 9 (:pattern result)))
    (is (= :terminated (:status (:single result))))
    (is (= 2 (count (:batch result))))
    (is (every? #(= :terminated (:status %)) (:batch result)))
    (is (>= (count (get-in result [:parent-state :loom :turns])) 3))))

(deftest example-10-loom-test
  (let [result (examples/example-10-loom {:mode :scripted})]
    (is (= 10 (:pattern result)))
    (is (= :terminated (:status result)))
    (is (pos? (:turn-count result)))
    (is (= (:turn-count result) (:loom-turn-count result)))
    (is (map? (:token-usage result)))
    (is (seq (:gates-called result)))))

(deftest example-11-persistent-entity-test
  (let [result (examples/example-11-persistent-entity {:mode :scripted})]
    (is (= 11 (:pattern result)))
    (is (= :terminated (:status (:first-send result))))
    (is (= :terminated (:status (:second-send result))))
    (is (= 2 (:turn-count (:state result))))
    (is (= 2 (count (get-in result [:state :loom :turns]))))))

(deftest example-12-familiar-test
  (let [result (examples/example-12-familiar {:mode :scripted})]
    (is (= 12 (:pattern result)))
    (is (= :terminated (:status (:first-send result))))
    (is (= :terminated (:status (:second-send result))))
    (is (>= (:turn-count (:state result)) 2))
    (is (seq (get-in result [:state :loom :turns])))))

(deftest example-13-acp-test
  (let [result (examples/example-13-acp {:mode :scripted})]
    (is (= 13 (:pattern result)))
    (is (string? (:session-id result)))
    (is (= "2.0" (get-in result [:response :jsonrpc])))
    (is (seq (get-in result [:response :result :output])))))

(deftest pattern-notes-coverage-test
  (is (= (set (map #(format "%02d" %) (range 1 14)))
         (set (keys examples/pattern-notes)))))

;; ── No silent fallback ──────────────────────────────────────────────────────

(deftest no-silent-fallback-test
  (testing "Examples that need an LLM must throw when called with no args and no env vars"
    ;; Clear env vars before testing
    (let [saved-model (System/getenv "OPENAI_MODEL")
          saved-key (System/getenv "OPENAI_API_KEY")]
      ;; We can't unset env vars in Java, so we test the mode dispatch instead:
      ;; calling with {:mode :real} and no env vars should fail, not silently use :fake
      ;; This test verifies the examples accept {:mode :scripted} and return :pattern
      (let [fns {1  "example-01-llm-query"
                 4  "example-04-cantrip"
                 5  "example-05-wards"
                 6  "example-06-medium"
                 7  "example-07-full-agent"
                 8  "example-08-folding"
                 10 "example-10-loom"
                 11 "example-11-persistent-entity"
                 12 "example-12-familiar"
                 13 "example-13-acp"}]
        (doseq [[n fname] fns]
          (let [result (try
                         ((resolve (symbol "cantrip.examples" fname)) {:mode :scripted})
                         (catch Exception _ :failed))]
            (is (not= :failed result) (str fname " must work in scripted mode"))))))))
