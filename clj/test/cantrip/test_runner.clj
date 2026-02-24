(ns cantrip.test-runner
  (:require [clojure.test :as t]
            [cantrip.domain-test]
            [cantrip.runtime-test]))

(defn -main [& _]
  (let [{:keys [fail error]} (t/run-tests 'cantrip.domain-test
                                          'cantrip.runtime-test)]
    (System/exit (if (zero? (+ fail error)) 0 1))))
