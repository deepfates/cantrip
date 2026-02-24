(ns cantrip.circle
  (:require [cantrip.gates :as gates]))

(defn- done-observation [args]
  (if (contains? args :answer)
    {:gate "done"
     :arguments (pr-str args)
     :result (:answer args)
     :is-error false}
    {:gate "done"
     :arguments (pr-str args)
     :result "missing required answer"
     :is-error true}))

(defn execute-tool-calls
  "Executes gate calls in-order for one turn and returns normalized observation.
   Stops after successful done gate."
  [circle tool-calls]
  (loop [calls tool-calls
         observation []
         terminated? false
         result nil]
    (if (or (empty? calls) terminated?)
      {:observation observation
       :terminated? terminated?
       :result result}
      (let [call (first calls)
            gate (gates/gate-keyword (:gate call))
            args (:args call)
            gate-name (name gate)]
        (cond
          (not (gates/gate-available? (:gates circle) gate))
          (recur (rest calls)
                 (conj observation
                       {:gate gate-name
                        :arguments (pr-str args)
                        :result "gate not available"
                        :is-error true})
                 false
                 nil)

          (= gate :done)
          (let [rec (done-observation args)]
            (if (:is-error rec)
              (recur (rest calls) (conj observation rec) false nil)
              (recur (rest calls) (conj observation rec) true (:result rec))))

          :else
          (recur (rest calls)
                 (conj observation
                       {:gate gate-name
                        :arguments (pr-str args)
                        :result "gate not implemented"
                        :is-error true})
                 false
                 nil))))))
