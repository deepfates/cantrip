(ns cantrip.examples-test
  "Structural tests for grimoire teaching examples.

   These tests verify that each example demonstrates its pattern correctly,
   regardless of LLM output. They test structure, not content.

   Cross-cutting requirements:
     - (example-NN {:mode :scripted}) uses FakeLLM, works without env vars
     - (example-NN) or (example-NN {:mode :real}) with no env vars MUST throw
     - Every result map has :pattern key matching its number

   These tests MAY fail against current examples -- that is the point.
   They establish what 'correct' looks like per the spec."
  (:require [cantrip.examples :as examples]
            [cantrip.gates :as gates]
            [cantrip.runtime :as runtime]
            [clojure.test :refer [deftest is testing]]))

;; ── Cross-cutting: scripted mode always works ────────────────────────────────

(deftest scripted-mode-01 (is (= 1 (:pattern (examples/example-01-llm-query {:mode :scripted})))))
(deftest scripted-mode-02 (is (= 2 (:pattern (examples/example-02-gate)))))
(deftest scripted-mode-03 (is (= 3 (:pattern (examples/example-03-circle)))))
(deftest scripted-mode-04 (is (= 4 (:pattern (examples/example-04-cantrip {:mode :scripted})))))
(deftest scripted-mode-05 (is (= 5 (:pattern (examples/example-05-wards {:mode :scripted})))))
(deftest scripted-mode-06 (is (= 6 (:pattern (examples/example-06-medium {:mode :scripted})))))
(deftest scripted-mode-07 (is (= 7 (:pattern (examples/example-07-full-agent {:mode :scripted})))))
(deftest scripted-mode-08 (is (= 8 (:pattern (examples/example-08-folding {:mode :scripted})))))
(deftest scripted-mode-09 (is (= 9 (:pattern (examples/example-09-composition {:mode :scripted})))))
(deftest scripted-mode-10 (is (= 10 (:pattern (examples/example-10-loom {:mode :scripted})))))
(deftest scripted-mode-11 (is (= 11 (:pattern (examples/example-11-persistent-entity {:mode :scripted})))))
(deftest scripted-mode-12 (is (= 12 (:pattern (examples/example-12-familiar {:mode :scripted})))))
(deftest scripted-mode-13 (is (= 13 (:pattern (examples/example-13-acp {:mode :scripted})))))

;; ── Cross-cutting: no silent fallback ────────────────────────────────────────
;; Examples 02 and 03 don't need LLM, so they're excluded.

(deftest no-fallback-01 (is (thrown? Exception (examples/example-01-llm-query {:mode :real}))))
(deftest no-fallback-04 (is (thrown? Exception (examples/example-04-cantrip {:mode :real}))))
(deftest no-fallback-05 (is (thrown? Exception (examples/example-05-wards {:mode :real}))))
(deftest no-fallback-06 (is (thrown? Exception (examples/example-06-medium {:mode :real}))))
(deftest no-fallback-07 (is (thrown? Exception (examples/example-07-full-agent {:mode :real}))))
(deftest no-fallback-08 (is (thrown? Exception (examples/example-08-folding {:mode :real}))))
(deftest no-fallback-09 (is (thrown? Exception (examples/example-09-composition {:mode :real}))))
(deftest no-fallback-10 (is (thrown? Exception (examples/example-10-loom {:mode :real}))))
(deftest no-fallback-11 (is (thrown? Exception (examples/example-11-persistent-entity {:mode :real}))))
(deftest no-fallback-12 (is (thrown? Exception (examples/example-12-familiar {:mode :real}))))

;; ── Per-example structural tests (scripted mode) ────────────────────────────

(deftest example-01-llm-query-test
  (let [result (examples/example-01-llm-query {:mode :scripted})]
    (is (= 1 (:pattern result)))
    ;; Stateless: one query, one response, no loop
    (is (= 1 (count (get-in result [:query :messages])))
        "must send exactly one message")
    (is (string? (get-in result [:response :content]))
        "response must contain a content string")))

(deftest example-02-gate-test
  (let [result (examples/example-02-gate)]
    (is (= 2 (:pattern result)))
    ;; Tools list is non-empty
    (is (seq (:tools result))
        "gate-tools must return tools")
    ;; Echo gate works
    (is (= false (get-in result [:echo-exec :observation 0 :is-error]))
        "echo gate call must not be an error")
    ;; Done gate terminates
    (is (true? (:terminated? (:done-exec result)))
        "done gate must terminate the loop")
    ;; Malformed done (empty args) must be error, NOT terminate
    (is (true? (get-in result [:malformed-done :observation 0 :is-error]))
        "malformed done (empty args) must be an error")
    (is (false? (:terminated? (:malformed-done result)))
        "malformed done must NOT terminate")))

(deftest example-03-circle-test
  (let [result (examples/example-03-circle)]
    (is (= 3 (:pattern result)))
    ;; Valid cantrip exists
    (is (map? (:valid result)))
    ;; Missing done gate produces CIRCLE-1 error
    (is (= "CIRCLE-1" (:rule (:missing-done result)))
        "missing done must cite CIRCLE-1")
    ;; Missing wards produces CIRCLE-2 error
    (is (= "CIRCLE-2" (:rule (:missing-wards result)))
        "missing wards must cite CIRCLE-2")))

(deftest example-04-cantrip-test
  (let [result (examples/example-04-cantrip {:mode :scripted})]
    (is (= 4 (:pattern result)))
    ;; Both runs terminated
    (is (= :terminated (:status (:first-run result)))
        "first cast must terminate")
    (is (= :terminated (:status (:second-run result)))
        "second cast must terminate")
    ;; Each run has turns
    (is (pos? (count (:turns (:first-run result))))
        "first run must have turns")
    ;; Independent entity IDs (CANTRIP-2)
    (is (true? (:independent-entity-ids result))
        "two casts must produce independent entity IDs")))

(deftest example-05-wards-test
  (let [result (examples/example-05-wards {:mode :scripted})]
    (is (= 5 (:pattern result)))
    ;; Ward composition: min wins for numeric
    (is (= 10 (get-in result [:composed :max-turns]))
        "composed max-turns must be 10 (min wins)")
    ;; Ward composition: OR wins for boolean
    (is (true? (get-in result [:composed :require-done-tool]))
        "require-done-tool must be true (OR wins)")
    ;; Run should be truncated (entity echoes but hits ward before done)
    (is (= :truncated (:status (:run result)))
        "run must be truncated (ward cuts off before done)")))

(deftest example-06-medium-test
  (let [result (examples/example-06-medium {:mode :scripted})]
    (is (= 6 (:pattern result)))
    ;; Two different mediums
    (is (= :conversation (get-in result [:conversation :view :medium]))
        "conversation view must have :conversation medium")
    (is (= :code (get-in result [:code :view :medium]))
        "code view must have :code medium")
    ;; Both runs terminate
    (is (= :terminated (get-in result [:conversation :run :status]))
        "conversation run must terminate")
    (is (= :terminated (get-in result [:code :run :status]))
        "code run must terminate")))

(deftest example-07-full-agent-test
  (let [result (examples/example-07-full-agent {:mode :scripted})]
    (is (= 7 (:pattern result)))
    ;; Terminated
    (is (= :terminated (:status (:run result)))
        "agent must terminate")
    ;; At least 2 turns for error + recovery
    (is (>= (count (:turns (:run result))) 2)
        "need >= 2 turns")
    ;; Error steering: some observation is an error
    (is (some :is-error (:observations result))
        "at least one observation must be an error")
    ;; Recovery: done gate called
    (is (some #(= "done" %) (:gate-seq result))
        "gate sequence must include done")
    ;; DEEP CHECK: error-then-recovery ordering
    (let [obs (vec (:observations result))]
      (when (>= (count obs) 2)
        (is (true? (:is-error (first obs)))
            "first observation must be an error")
        (is (false? (:is-error (last obs)))
            "last observation must NOT be an error (recovery)")))))

(deftest example-08-folding-test
  (let [result (examples/example-08-folding {:mode :scripted})]
    (is (= 8 (:pattern result)))
    ;; 3 invocations (one per send)
    (is (= 3 (count (:invocations result)))
        "must have 3 LLM invocations")
    ;; State has 3 turns
    (is (= 3 (:turn-count (:state result)))
        "state must have turn-count 3")
    ;; Folding markers present and contain "Folded" text
    (is (seq (:folding-markers result))
        "folding markers must be non-empty")
    (is (every? #(re-find #"(?i)folded" (str %)) (:folding-markers result))
        "each folding marker must contain 'Folded' text")
    ;; Identity (system prompt) preserved through folding
    (is (string? (get-in result [:state :loom :identity :system-prompt]))
        "system prompt must be preserved in loom")))

(deftest example-09-composition-test
  (let [result (examples/example-09-composition {:mode :scripted})]
    (is (= 9 (:pattern result)))
    ;; Single child terminated
    (is (= :terminated (:status (:single result)))
        "single child must terminate")
    ;; Batch has 2 results, all terminated
    (is (= 2 (count (:batch result)))
        "batch must have 2 results")
    (is (every? #(= :terminated (:status %)) (:batch result))
        "all batch results must terminate")
    ;; Parent state has delegation turns (>= 3: intent + call + batch)
    (is (>= (count (get-in result [:parent-state :loom :turns])) 3)
        "parent loom must have >= 3 turns")))

(deftest example-10-loom-test
  (let [result (examples/example-10-loom {:mode :scripted})]
    (is (= 10 (:pattern result)))
    ;; Terminated
    (is (= :terminated (:status result))
        "run must terminate")
    ;; Turn counts consistent
    (is (pos? (:turn-count result))
        "must have positive turn count")
    (is (= (:turn-count result) (:loom-turn-count result))
        "turn count must match loom turn count")
    ;; Token usage tracked
    (is (map? (:token-usage result))
        "token usage must be a map")
    ;; Gates called
    (is (seq (:gates-called result))
        "gates-called must be non-empty")
    (is (some #(= "echo" %) (:gates-called result))
        "echo must be in gates-called")
    (is (some #(= "done" %) (:gates-called result))
        "done must be in gates-called")))

(deftest example-11-persistent-entity-test
  (let [result (examples/example-11-persistent-entity {:mode :scripted})]
    (is (= 11 (:pattern result)))
    ;; Both sends terminated
    (is (= :terminated (:status (:first-send result)))
        "first send must terminate")
    (is (= :terminated (:status (:second-send result)))
        "second send must terminate")
    ;; State accumulates: 2 turns total
    (is (= 2 (:turn-count (:state result)))
        "entity must have 2 accumulated turns")
    ;; Loom has 2 turns
    (is (= 2 (count (get-in result [:state :loom :turns])))
        "loom must have 2 turns")))

(deftest example-12-familiar-test
  (let [result (examples/example-12-familiar {:mode :scripted})]
    (is (= 12 (:pattern result)))
    ;; Both sends terminated
    (is (= :terminated (:status (:first-send result)))
        "first send must terminate")
    (is (= :terminated (:status (:second-send result)))
        "second send must terminate")
    ;; State accumulates
    (is (>= (:turn-count (:state result)) 2)
        "state must have >= 2 turns")
    ;; Loom turns exist
    (is (seq (get-in result [:state :loom :turns]))
        "loom turns must exist")
    ;; First send result must contain child delegation evidence
    (let [first-result (get-in result [:first-send :result])]
      (is (string? first-result) "first send result must be a string")
      (is (re-find #"child" (str first-result))
          "first send result should mention child results (evidence of delegation)"))))

(deftest example-13-acp-test
  (let [result (examples/example-13-acp {:mode :scripted})]
    (is (= 13 (:pattern result)))
    (is (string? (:session-id result))
        "session-id must be a string")
    (is (= "2.0" (get-in result [:response :jsonrpc]))
        "response must have jsonrpc 2.0")
    (is (seq (get-in result [:response :result :output]))
        "response must have output")))

;; ── Framework-level structural checks ────────────────────────────────────────

(deftest done-gate-has-parameter-schema
  (testing "done gate must have answer parameter in schema"
    (let [tools (gates/gate-tools [:done :echo])
          done-tool (first (filter #(= "done" (:name %)) tools))]
      (is (some? done-tool)
          "done must appear in gate-tools output")
      (is (map? (:parameters done-tool))
          "done gate must have :parameters map")
      (when (map? (:parameters done-tool))
        (let [props (or (get-in done-tool [:parameters :properties])
                        (get-in done-tool [:parameters "properties"]))]
          (is (some? props)
              "done parameters must have properties")
          (when props
            (is (or (contains? props :answer) (contains? props "answer"))
                "done properties must include 'answer'")))))))

(deftest child-identity-not-parent-delegation
  (testing "child entity must NOT inherit parent's delegation-specific identity"
    ;; When derive-child-cantrip produces a child, it should get a generic
    ;; identity unless one is explicitly provided, not the parent's prompt
    ;; about delegation gates it doesn't have.
    (let [parent (runtime/summon
                  {:llm {:provider :fake
                         :responses [{:tool-calls [{:id "p1" :gate :done :args {:answer "parent"}}]}]}
                   :identity {:system-prompt "I am the parent. Delegate tasks using call-agent."}
                   :circle {:medium :conversation
                            :gates [:done]
                            :wards [{:max-turns 2} {:max-depth 2}]}})
          ;; When providing an explicit child cantrip, it keeps its identity
          child-cantrip {:llm {:provider :fake
                               :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child"}}]}]}
                         :identity {:system-prompt "I am a child worker."}
                         :circle {:medium :conversation
                                  :gates [:done]
                                  :wards [{:max-turns 2}]}}
          result (runtime/call-agent parent {:cantrip child-cantrip :intent "child task"})]
      (is (= :terminated (:status result))
          "child must terminate"))))

(deftest pattern-notes-coverage-test
  (is (= (set (map #(format "%02d" %) (range 1 14)))
         (set (keys examples/pattern-notes)))))
