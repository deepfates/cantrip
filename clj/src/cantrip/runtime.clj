(ns cantrip.runtime
  (:refer-clojure :exclude [cast])
  (:require [cantrip.crystal :as crystal]
            [cantrip.domain :as domain]))

(defn- max-turns [cantrip]
  (or (some :max-turns (get-in cantrip [:circle :wards]))
      1))

(defn- require-done-tool? [cantrip]
  (true? (get-in cantrip [:call :require-done-tool])))

(defn- tool-choice [cantrip]
  (or (get-in cantrip [:call :tool-choice])
      :auto))

(defn- normalize-gate [gate]
  (cond
    (keyword? gate) gate
    (string? gate) (keyword gate)
    :else gate))

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

(defn- process-tool-calls [tool-calls]
  (loop [calls tool-calls
         obs []
         terminated? false
         result nil]
    (if (or (empty? calls) terminated?)
      {:observation obs
       :terminated? terminated?
       :result result}
      (let [call (first calls)
            gate (normalize-gate (:gate call))
            args (:args call)]
        (case gate
          :done (let [rec (done-observation args)]
                  (if (:is-error rec)
                    (recur (rest calls) (conj obs rec) false nil)
                    (recur (rest calls) (conj obs rec) true (:result rec))))
          (let [rec {:gate (name gate)
                     :arguments (pr-str args)
                     :result "gate not implemented"
                     :is-error true}]
            (recur (rest calls) (conj obs rec) false nil)))))))

(defn new-cantrip
  "Constructs and validates a cantrip value."
  [cantrip]
  (domain/validate-cantrip! cantrip))

(defn cast
  "Runs one cast (one intent episode) and returns a result map."
  [cantrip intent]
  (domain/validate-cantrip! cantrip)
  (domain/require-intent! intent)
  (let [entity-id (str (random-uuid))
        turn-limit (max-turns cantrip)
        done-required? (require-done-tool? cantrip)
        selected-tool-choice (tool-choice cantrip)]
    (loop [turn-index 0
           turns []
           previous-tool-call-ids []]
      (if (>= turn-index turn-limit)
        {:entity-id entity-id
         :status :truncated
         :result nil
         :turns turns}
        (let [utterance (crystal/query (:crystal cantrip)
                                       turn-index
                                       {:tool-choice selected-tool-choice
                                        :previous-tool-call-ids previous-tool-call-ids})
              tool-calls (vec (:tool-calls utterance))
              {:keys [observation terminated? result]} (process-tool-calls tool-calls)
              text-only? (and (empty? tool-calls)
                              (string? (:content utterance)))
              done-by-text? (and text-only? (not done-required?))
              turn-record {:sequence (inc turn-index)
                           :utterance utterance
                           :observation observation
                           :terminated (or terminated? done-by-text?)
                           :truncated false}
              next-turns (conj turns turn-record)]
          (cond
            terminated? {:entity-id entity-id
                         :status :terminated
                         :result result
                         :turns next-turns}

            done-by-text? {:entity-id entity-id
                           :status :terminated
                           :result (:content utterance)
                           :turns next-turns}

            :else (recur (inc turn-index)
                         next-turns
                         (mapv :id tool-calls))))))))

(defn invoke
  "Creates a persistent entity handle for multi-cast sessions.
   Invocation lifecycle is implemented in upcoming slices."
  [cantrip]
  (domain/validate-cantrip! cantrip)
  {:entity-id (str (random-uuid))
   :cantrip cantrip
   :status :ready})
