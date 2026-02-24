(ns cantrip.test-runner
  (:require [clojure.test :as t]
            [cantrip.circle-test]
            [cantrip.crystal-test]
            [cantrip.domain-test]
            [cantrip.loom-test]
            [cantrip.medium-test]
            [cantrip.runtime-test]))

(defn -main [& _]
  (let [{:keys [fail error]} (t/run-tests 'cantrip.circle-test
                                          'cantrip.crystal-test
                                          'cantrip.domain-test
                                          'cantrip.loom-test
                                          'cantrip.medium-test
                                          'cantrip.runtime-test)]
    (System/exit (if (zero? (+ fail error)) 0 1))))
