(ns cantrip.domain
  (:require [cantrip.gates :as gates]
            [clojure.string :as str]))

(defn- has-done-gate? [circle]
  (gates/gate-available? (:gates circle) :done))

(defn- has-truncation-ward? [circle]
  (boolean
   (some #(or (contains? % :max-turns)
              (contains? % :timeout-ms)
              (contains? % :max-tokens))
         (:wards circle))))

(defn- validate-circle! [circle]
  (when-not (map? circle)
    (throw (ex-info "circle must be a map" {:rule "CANTRIP-1"})))

  (when (and (contains? circle :medium) (contains? circle :circle-type))
    (throw (ex-info "circle must declare exactly one medium"
                    {:rule "CIRCLE-12"})))

  (when-not (contains? circle :medium)
    (throw (ex-info "circle must declare medium" {:rule "CIRCLE-12"})))

  (when-not (has-done-gate? circle)
    (throw (ex-info "circle must have a done gate" {:rule "CIRCLE-1"})))

  (when-not (has-truncation-ward? circle)
    (throw (ex-info "cantrip must have at least one truncation ward"
                    {:rule "CIRCLE-2"}))))

(defn validate-cantrip!
  "Validates cantrip shape and core invariants.
   Returns the normalized cantrip map or throws ex-info with rule metadata."
  [cantrip]
  (when-not (map? cantrip)
    (throw (ex-info "cantrip must be a map" {:rule "CANTRIP-1"})))
  (doseq [k [:crystal :call :circle]]
    (when-not (contains? cantrip k)
      (throw (ex-info (str "cantrip requires " (name k))
                      {:rule "CANTRIP-1" :missing k}))))
  (validate-circle! (:circle cantrip))
  cantrip)

(defn require-intent!
  "Validates INTENT-1."
  [intent]
  (when (or (nil? intent)
            (and (string? intent) (str/blank? intent)))
    (throw (ex-info "intent is required" {:rule "INTENT-1"})))
  intent)
