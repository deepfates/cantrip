(ns cantrip.circle-test
  (:require [clojure.test :refer [deftest is]]
            [cantrip.circle :as circle]))

(def circle-config
  {:medium :conversation
   :gates [:done :echo]
   :wards [{:max-turns 5}]})

(deftest executes-in-order-and-stops-after-done
  (let [res (circle/execute-tool-calls
             circle-config
             [{:id "call_1" :gate :echo :args {:text "before"}}
              {:id "call_2" :gate :done :args {:answer "ok"}}
              {:id "call_3" :gate :echo :args {:text "after"}}])]
    (is (true? (:terminated? res)))
    (is (= "ok" (:result res)))
    (is (= ["echo" "done"] (mapv :gate (:observation res))))))

(deftest failed-gate-is-observable-error
  (let [res (circle/execute-tool-calls
             circle-config
             [{:id "call_1" :gate :missing :args {:x 1}}])
        rec (first (:observation res))]
    (is (= false (:terminated? res)))
    (is (true? (:is-error rec)))
    (is (= "gate not available" (:result rec)))))

(deftest malformed-done-does-not-terminate
  (let [res (circle/execute-tool-calls
             circle-config
             [{:id "call_1" :gate :done :args {}}
              {:id "call_2" :gate :done :args {:answer "fixed"}}])]
    (is (true? (:terminated? res)))
    (is (= "fixed" (:result res)))
    (is (= 2 (count (:observation res))))
    (is (true? (-> res :observation first :is-error)))))

(deftest read-gate-blocks-root-escape
  (let [circle {:medium :conversation
                :gates [{:name :done}
                        {:name :read :dependencies {:root "/safe"}}]
                :wards [{:max-turns 2}]}
        res (circle/execute-tool-calls
             circle
             [{:id "call_1" :gate :read :args {:path "../secrets.txt"}}]
             {:filesystem {"/safe/ok.txt" "ok"}})]
    (is (= "path escapes root" (-> res :observation first :result)))
    (is (false? (-> res :observation first :is-error)))))
