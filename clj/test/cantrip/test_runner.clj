(ns cantrip.test-runner
  (:require [clojure.test :as t]
            [cantrip.acp-test]
            [cantrip.circle-test]
            [cantrip.composition-test]
            [cantrip.crystal-test]
            [cantrip.domain-test]
            [cantrip.examples-test]
            [cantrip.gates-test]
            [cantrip.loom-test]
            [cantrip.medium-test]
            [cantrip.openai-test]
            [cantrip.redaction-test]
            [cantrip.runtime-test]))

(defn -main [& _]
  (let [{:keys [fail error]} (t/run-tests 'cantrip.acp-test
                                          'cantrip.circle-test
                                          'cantrip.composition-test
                                          'cantrip.crystal-test
                                          'cantrip.domain-test
                                          'cantrip.examples-test
                                          'cantrip.gates-test
                                          'cantrip.loom-test
                                          'cantrip.medium-test
                                          'cantrip.openai-test
                                          'cantrip.redaction-test
                                          'cantrip.runtime-test)]
    (System/exit (if (zero? (+ fail error)) 0 1))))
