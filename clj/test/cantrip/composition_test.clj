(ns cantrip.composition-test
  (:require [cantrip.runtime :as runtime]
            [clojure.test :refer [deftest is]]))

(def parent-cantrip
  {:crystal {:provider :fake
             :responses-by-invocation true
             :responses [{:tool-calls [{:id "p1" :gate :done :args {:answer "parent-1"}}]}
                         {:tool-calls [{:id "p2" :gate :done :args {:answer "parent-2"}}]}]}
   :call {:system-prompt "parent"}
   :circle {:medium :conversation
            :gates [:done :echo]
            :wards [{:max-turns 3}]}})

(deftest call-agent-links-child-root-to-parent-turn
  (let [entity (runtime/invoke parent-cantrip)
        _ (runtime/cast-intent entity "start parent")
        parent-last-id (:id (last @(:turn-history entity)))
        child-cantrip {:crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child"}}]}]}
                       :call {:system-prompt "child"}
                       :circle {:medium :conversation
                                :gates [:done]
                                :wards [{:max-turns 2}]}}
        result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})
        child-first-turn (:turns result)]
    (is (= :terminated (:status result)))
    (is (= "child" (:result result)))
    (is (= parent-last-id (:parent-id (first child-first-turn))))))

(deftest call-agent-enforces-child-circle-subset
  (let [entity (runtime/invoke parent-cantrip)
        child-cantrip {:crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child"}}]}]}
                       :call {:system-prompt "child"}
                       :circle {:medium :conversation
                                :gates [:done :read]
                                :wards [{:max-turns 2}]}}
        result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})]
    (is (= :error (:status result)))
    (is (= "cannot grant gate: child gates must be subset of parent gates" (:error result)))))

(deftest call-agent-enforces-depth-ward
  (let [entity (runtime/invoke (assoc-in parent-cantrip [:circle :wards] [{:max-turns 3} {:max-depth 0}]))
        child-cantrip {:crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child"}}]}]}
                       :call {:system-prompt "child"}
                       :circle {:medium :conversation
                                :gates [:done]
                                :wards [{:max-turns 2}]}}
        result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})]
    (is (= :error (:status result)))
    (is (= "max depth exceeded" (:error result)))))

(deftest call-agent-batch-preserves-request-order
  (let [entity (runtime/invoke parent-cantrip)
        child-a {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "a1" :gate :done :args {:answer "a"}}]}]}
                 :call {:system-prompt "a"}
                 :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}}
        child-b {:crystal {:provider :fake
                           :responses [{:tool-calls [{:id "b1" :gate :done :args {:answer "b"}}]}]}
                 :call {:system-prompt "b"}
                 :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}}
        results (runtime/call-agent-batch entity [{:cantrip child-a :intent "one"}
                                                  {:cantrip child-b :intent "two"}])]
    (is (= ["a" "b"] (mapv :result results)))))

(deftest parent-survives-child-error
  (let [entity (runtime/invoke parent-cantrip)
        child-cantrip {:crystal {:provider :fake
                                 :responses [{:error {:status 500 :message "boom"}}]}
                       :call {:system-prompt "child"}
                       :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}}
        child-result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})
        parent-result (runtime/cast-intent entity "parent continues")]
    (is (= :error (:status child-result)))
    (is (= :terminated (:status parent-result)))
    (is (= "parent-1" (:result parent-result)))))
(ns cantrip.composition-test)
