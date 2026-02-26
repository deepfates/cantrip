(ns cantrip.circle
  (:require [cantrip.gates :as gates]
            [clojure.string :as str]))

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

(defn- removed-gates
  [circle]
  (->> (:wards circle)
       (keep (fn [ward]
               (or (:remove-gate ward)
                   (:remove_gate ward))))
       (map gates/gate-keyword)
       set))

(defn- gate-spec
  [circle gate]
  (let [gate-id (gates/gate-keyword gate)
        gates-def (:gates circle)]
    (cond
      (map? gates-def) (get gates-def gate-id)
      (sequential? gates-def) (some (fn [g]
                                      (when (and (map? g)
                                                 (= gate-id (gates/gate-keyword (:name g))))
                                        g))
                                    gates-def)
      :else nil)))

(defn- read-path
  [spec args dependencies]
  (let [filesystem (:filesystem dependencies)
        root (get-in spec [:dependencies :root])
        path (:path args)
        path-escape? (or (not (string? path))
                         (.startsWith path "/")
                         (some #{".." "."} (remove empty? (str/split path #"/+"))))
        rooted (if (and (string? root) (string? path) (not (.startsWith path "/")))
                 (str root "/" path)
                 path)]
    (if (and (string? root) path-escape?)
      "path escapes root"
      (or (get filesystem rooted)
          (get filesystem path)
          "file not found"))))

(defn- gate-observation
  [circle gate args dependencies]
  (let [spec (gate-spec circle gate)
        behavior (or (:behavior spec) (:result-behavior spec))]
    (cond
      (or (= behavior :throw) (= behavior "throw"))
      {:result (or (:error spec) "gate error")
       :is-error true}

      (or (= behavior :delay) (= behavior "delay"))
      (do
        (Thread/sleep (long (or (:delay-ms spec) (:delay_ms spec) 0)))
        {:result (or (:result spec) "completed")
         :is-error false})

      (= (gates/gate-keyword gate) :echo)
      {:result (:text args)
       :is-error false}

      (= (gates/gate-keyword gate) :read)
      {:result (read-path spec args dependencies)
       :is-error false}

      (contains? spec :result)
      {:result (:result spec)
       :is-error false}

      :else
      {:result "gate not implemented"
       :is-error true})))

(defn execute-tool-calls
  "Executes gate calls in-order for one turn and returns normalized observation.
   Stops after successful done gate."
  ([circle tool-calls]
   (execute-tool-calls circle tool-calls {}))
  ([circle tool-calls dependencies]
   (loop [calls tool-calls
          observation []
          terminated? false
          result nil
          removed (removed-gates circle)]
     (if (or (empty? calls) terminated?)
       {:observation observation
        :terminated? terminated?
        :result result}
       (let [call (first calls)
             gate (gates/gate-keyword (:gate call))
             args (:args call)
             gate-name (name gate)]
         (cond
           (or (contains? removed gate)
               (not (gates/gate-available? (:gates circle) gate)))
           (recur (rest calls)
                  (conj observation
                        {:gate gate-name
                         :arguments (pr-str args)
                         :result "gate not available"
                         :is-error true})
                  false
                  nil
                  removed)

           (= gate :done)
           (let [rec (done-observation args)]
             (if (:is-error rec)
               (recur (rest calls) (conj observation rec) false nil removed)
               (recur (rest calls) (conj observation rec) true (:result rec) removed)))

           :else
           (let [{:keys [result is-error]} (gate-observation circle gate args dependencies)]
             (recur (rest calls)
                    (conj observation
                          {:gate gate-name
                           :arguments (pr-str args)
                           :result result
                           :is-error is-error})
                    false
                    nil
                    removed))))))))
