(ns cantrip.composition-test
  (:require [cantrip.runtime :as runtime]
            [clojure.test :refer [deftest is]]))

(def parent-cantrip
  {:llm {:provider :fake
             :responses-by-invocation true
             :responses [{:tool-calls [{:id "p1" :gate :done :args {:answer "parent-1"}}]}
                         {:tool-calls [{:id "p2" :gate :done :args {:answer "parent-2"}}]}]}
   :identity {:system-prompt "parent"}
   :circle {:medium :conversation
            :gates [:done :echo]
            :wards [{:max-turns 3}]}})

(deftest call-agent-links-child-root-to-parent-turn
  (let [entity (runtime/summon parent-cantrip)
        _ (runtime/send entity "start parent")
        parent-last-id (:id (last @(:turn-history entity)))
        child-cantrip {:llm {:provider :fake
                                 :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child"}}]}]}
                       :identity {:system-prompt "child"}
                       :circle {:medium :conversation
                                :gates [:done]
                                :wards [{:max-turns 2}]}}
        result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})
        child-first-turn (:turns result)]
    (is (= :terminated (:status result)))
    (is (= "child" (:result result)))
    (is (= parent-last-id (:parent-id (first child-first-turn))))))

(deftest call-agent-enforces-depth-ward
  (let [entity (runtime/summon (assoc-in parent-cantrip [:circle :wards] [{:max-turns 3} {:max-depth 0}]))
        child-cantrip {:llm {:provider :fake
                                 :responses [{:tool-calls [{:id "c1" :gate :done :args {:answer "child"}}]}]}
                       :identity {:system-prompt "child"}
                       :circle {:medium :conversation
                                :gates [:done]
                                :wards [{:max-turns 2}]}}
        result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})]
    (is (= :error (:status result)))
    (is (= "max depth exceeded" (:error result)))))

(deftest call-agent-batch-preserves-request-order
  (let [entity (runtime/summon parent-cantrip)
        child-a {:llm {:provider :fake
                           :responses [{:tool-calls [{:id "a1" :gate :done :args {:answer "a"}}]}]}
                 :identity {:system-prompt "a"}
                 :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}}
        child-b {:llm {:provider :fake
                           :responses [{:tool-calls [{:id "b1" :gate :done :args {:answer "b"}}]}]}
                 :identity {:system-prompt "b"}
                 :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}}
        results (runtime/call-agent-batch entity [{:cantrip child-a :intent "one"}
                                                  {:cantrip child-b :intent "two"}])]
    (is (= ["a" "b"] (mapv :result results)))))

(deftest parent-survives-child-error
  (let [entity (runtime/summon parent-cantrip)
        child-cantrip {:llm {:provider :fake
                                 :responses [{:error {:status 500 :message "boom"}}]}
                       :identity {:system-prompt "child"}
                       :circle {:medium :conversation :gates [:done] :wards [{:max-turns 2}]}}
        child-result (runtime/call-agent entity {:cantrip child-cantrip :intent "child task"})
        parent-result (runtime/send entity "parent continues")]
    (is (= :error (:status child-result)))
    (is (= :terminated (:status parent-result)))
    (is (= "parent-1" (:result parent-result)))))
(ns cantrip.composition-test)
