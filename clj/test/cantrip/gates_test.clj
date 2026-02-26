(ns cantrip.gates-test
  (:require [cantrip.gates :as gates]
            [clojure.test :refer [deftest is]]))

(deftest gate-name-normalization
  (is (= "done" (gates/gate-name :done)))
  (is (= "echo" (gates/gate-name "echo")))
  (is (= "read" (gates/gate-name {:name :read}))))

(deftest gate-tools-projection
  (is (= [{:name "done"} {:name "echo"} {:name "read" :parameters {:type "object"}}]
         (gates/gate-tools [:done "echo" {:name :read :parameters {:type "object"}}]))))

(deftest gate-availability
  (is (true? (gates/gate-available? [:done {:name :read}] :read)))
  (is (true? (gates/gate-available? {:done {} :echo {}} "done")))
  (is (false? (gates/gate-available? [:done] :missing))))
