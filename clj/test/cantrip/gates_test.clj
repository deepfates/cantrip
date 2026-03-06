(ns cantrip.gates-test
  (:require [cantrip.gates :as gates]
            [clojure.test :refer [deftest is]]))

(deftest gate-name-normalization
  (is (= "done" (gates/gate-name :done)))
  (is (= "echo" (gates/gate-name "echo")))
  (is (= "read" (gates/gate-name {:name :read}))))

(deftest gate-tools-projection
  (let [tools (gates/gate-tools [:done "echo" {:name :read :parameters {:type "object"}}])]
    ;; done gate gets default answer parameter schema
    (is (= "done" (:name (first tools))))
    (is (map? (:parameters (first tools))))
    (is (= "string" (get-in (first tools) [:parameters :properties :answer :type]))
        "done gate parameters must include answer with type string")
    ;; echo gate gets default empty parameters
    (is (= {:name "echo" :parameters {}} (second tools)))
    ;; read gate keeps its explicit parameters
    (is (= {:name "read" :parameters {:type "object"}} (nth tools 2)))))

(deftest gate-availability
  (is (true? (gates/gate-available? [:done {:name :read}] :read)))
  (is (true? (gates/gate-available? {:done {} :echo {}} "done")))
  (is (false? (gates/gate-available? [:done] :missing))))
