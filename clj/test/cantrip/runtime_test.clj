(ns cantrip.runtime-test
  (:require [clojure.test :refer [deftest is testing]]
            [cantrip.runtime :as runtime]))

(def valid-cantrip
  {:crystal {:provider :fake}
   :call {:system-prompt "test"}
   :circle {:medium :conversation
            :gates [:done]
            :wards [{:max-turns 2}]}})

(deftest invoke-returns-entity-handle
  (testing "invoke returns an entity map with id and status"
    (let [entity (runtime/invoke valid-cantrip)]
      (is (string? (:entity-id entity)))
      (is (= :ready (:status entity))))))

(deftest cast-terminates-on-successful-done
  (let [cantrip (assoc valid-cantrip
                       :crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "call_1"
                                                            :gate :done
                                                            :args {:answer "ok"}}]}]})
        result (runtime/cast cantrip "hello")]
    (is (= :terminated (:status result)))
    (is (= "ok" (:result result)))
    (is (= 1 (count (:turns result))))))

(deftest malformed-done-does-not-terminate
  (let [cantrip (assoc valid-cantrip
                       :crystal {:provider :fake
                                 :responses [{:tool-calls [{:id "call_1"
                                                            :gate :done
                                                            :args {}}]}
                                             {:tool-calls [{:id "call_2"
                                                            :gate :done
                                                            :args {:answer "fixed"}}]}]})
        result (runtime/cast cantrip "hello")
        t1 (first (:turns result))]
    (is (= :terminated (:status result)))
    (is (= "fixed" (:result result)))
    (is (= 2 (count (:turns result))))
    (is (true? (-> t1 :observation first :is-error)))))

(deftest text-only-termination-default
  (let [cantrip (assoc valid-cantrip
                       :crystal {:provider :fake
                                 :responses [{:content "plain response"}]})
        result (runtime/cast cantrip "hello")]
    (is (= :terminated (:status result)))
    (is (= "plain response" (:result result)))
    (is (= 1 (count (:turns result))))))

(deftest text-only-continues-when-done-required
  (let [cantrip (-> valid-cantrip
                    (assoc :call {:system-prompt "test"
                                  :require-done-tool true})
                    (assoc :crystal {:provider :fake
                                     :responses [{:content "thinking"}
                                                 {:tool-calls [{:id "call_1"
                                                                :gate :done
                                                                :args {:answer "42"}}]}]}))
        result (runtime/cast cantrip "hello")]
    (is (= :terminated (:status result)))
    (is (= "42" (:result result)))
    (is (= 2 (count (:turns result))))))

(deftest truncates-when-max-turns-hit
  (let [cantrip (-> valid-cantrip
                    (assoc :call {:system-prompt "test"
                                  :require-done-tool true})
                    (assoc :crystal {:provider :fake
                                     :responses [{:content "a"}
                                                 {:content "b"}
                                                 {:content "c"}]}))
        result (runtime/cast cantrip "hello")]
    (is (= :truncated (:status result)))
    (is (nil? (:result result)))
    (is (= 2 (count (:turns result))))))
