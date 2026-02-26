(ns cantrip.domain-test
  (:require [clojure.test :refer [deftest is testing]]
            [cantrip.domain :as domain]))

(deftest validate-cantrip-core-shape
  (testing "CANTRIP-1 requires crystal, call, and circle"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"cantrip requires crystal"
                          (domain/validate-cantrip!
                           {:call {} :circle {:medium :conversation
                                              :gates [:done]
                                              :wards [{:max-turns 1}]}})))))

(deftest circle-invariants
  (testing "CIRCLE-1 requires done gate"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"done gate"
                          (domain/validate-cantrip!
                           {:crystal {}
                            :call {}
                            :circle {:medium :conversation
                                     :gates [:echo]
                                     :wards [{:max-turns 2}]}}))))

  (testing "CIRCLE-2 requires truncation ward"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"truncation ward"
                          (domain/validate-cantrip!
                           {:crystal {}
                            :call {}
                            :circle {:medium :conversation
                                     :gates [:done]
                                     :wards []}}))))

  (testing "CIRCLE-12 rejects conflicting medium declarations"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"exactly one medium"
                          (domain/validate-cantrip!
                           {:crystal {}
                            :call {}
                            :circle {:medium :code
                                     :circle-type :tool
                                     :gates [:done]
                                     :wards [{:max-turns 2}]}})))))

(deftest intent-required
  (testing "INTENT-1 rejects nil or blank intent"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"intent is required"
                          (domain/require-intent! nil)))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"intent is required"
                          (domain/require-intent! "  ")))))

(deftest ward-validation
  (testing "new ward values must be valid"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"max-batch-size must be a positive integer"
                          (domain/validate-cantrip!
                           {:crystal {}
                            :call {}
                            :circle {:medium :conversation
                                     :gates [:done]
                                     :wards [{:max-turns 2} {:max-batch-size 0}]}})))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"max-eval-ms must be a positive integer"
                          (domain/validate-cantrip!
                           {:crystal {}
                            :call {}
                            :circle {:medium :code
                                     :gates [:done]
                                     :wards [{:max-turns 2} {:max_eval_ms "nope"}]}})))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"allow-require must be boolean"
                          (domain/validate-cantrip!
                           {:crystal {}
                            :call {}
                            :circle {:medium :code
                                     :gates [:done]
                                     :wards [{:max-turns 2} {:allow_require :yes}]}})))))
