(ns cantrip.runtime
  (:refer-clojure :exclude [cast])
  (:require [cantrip.crystal :as crystal]
            [cantrip.domain :as domain]
            [cantrip.loom :as loom]
            [cantrip.medium :as medium]))

(defn- max-turns [cantrip]
  (or (some :max-turns (get-in cantrip [:circle :wards]))
      1))

(defn- require-done-tool? [cantrip]
  (true? (get-in cantrip [:call :require-done-tool])))

(defn- tool-choice [cantrip]
  (or (get-in cantrip [:call :tool-choice])
      :auto))

(defn- normalize-gate-name [gate]
  (cond
    (keyword? gate) (name gate)
    (string? gate) gate
    :else (str gate)))

(defn- gate->tool [gate]
  (cond
    (keyword? gate) {:name (name gate)}
    (string? gate) {:name gate}
    (map? gate) {:name (normalize-gate-name (:name gate))
                 :parameters (or (:parameters gate) {})}
    :else {:name (normalize-gate-name gate)}))

(defn- circle-tools [circle]
  (let [gates (:gates circle)]
    (cond
      (map? gates) (mapv (fn [[k v]]
                           (merge {:name (normalize-gate-name k)}
                                  (when (map? v) {:parameters (or (:parameters v) {})})))
                         gates)
      (sequential? gates) (mapv gate->tool gates)
      :else [])))

(defn- turn->messages [turn]
  (let [utterance (:utterance turn)
        assistant-msg (cond-> {:role :assistant}
                        (string? (:content utterance))
                        (assoc :content (:content utterance))
                        (seq (:tool-calls utterance))
                        (assoc :tool-calls (vec (:tool-calls utterance))))
        tool-msgs (mapv (fn [record]
                          {:role :tool
                           :name (:gate record)
                           :content (str (:result record))})
                        (:observation turn))]
    (into [assistant-msg] tool-msgs)))

(defn- build-messages [cantrip intent prior-turns current-cast-turns]
  (let [system-prompt (get-in cantrip [:call :system-prompt])
        base (cond-> []
               (string? system-prompt)
               (conj {:role :system :content system-prompt})
               :always
               (conj {:role :user :content intent}))
        turns (concat prior-turns current-cast-turns)]
    (reduce (fn [acc turn]
              (into acc (turn->messages turn)))
            base
            turns)))

(defn- run-cast
  [entity-id cantrip intent prior-turns initial-loom]
  (let [turn-limit (max-turns cantrip)
        done-required? (require-done-tool? cantrip)
        selected-tool-choice (tool-choice cantrip)
        tools (circle-tools (:circle cantrip))]
    (loop [turn-index 0
           turns []
           loom-state initial-loom
           previous-tool-call-ids []]
      (if (>= turn-index turn-limit)
        {:entity-id entity-id
         :intent intent
         :status :truncated
         :result nil
         :turns turns
         :new-turns turns
         :loom loom-state}
        (let [messages (build-messages cantrip intent prior-turns turns)
              utterance (crystal/query (:crystal cantrip)
                                       {:turn-index turn-index
                                        :messages messages
                                        :tools tools
                                        :tool-choice selected-tool-choice
                                        :previous-tool-call-ids previous-tool-call-ids})
              tool-calls (vec (:tool-calls utterance))
              {:keys [observation terminated? result]} (medium/execute-utterance
                                                       (:circle cantrip)
                                                       utterance
                                                       (get-in cantrip [:circle :dependencies]))
              text-only? (and (empty? tool-calls)
                              (string? (:content utterance)))
              done-by-text? (and text-only? (not done-required?))
              turn-record {:sequence (inc turn-index)
                           :utterance utterance
                           :observation observation
                           :terminated (or terminated? done-by-text?)
                           :truncated false}
              [next-loom _] (loom/append-turn loom-state turn-record)
              next-turns (conj turns turn-record)]
          (cond
            terminated? {:entity-id entity-id
                         :intent intent
                         :status :terminated
                         :result result
                         :turns next-turns
                         :new-turns next-turns
                         :loom next-loom}

            done-by-text? {:entity-id entity-id
                           :intent intent
                           :status :terminated
                           :result (:content utterance)
                           :turns next-turns
                           :new-turns next-turns
                           :loom next-loom}

            :else (recur (inc turn-index)
                         next-turns
                         next-loom
                         (mapv :id tool-calls))))))))

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
        initial-loom (loom/new-loom (:call cantrip))]
    (dissoc (run-cast entity-id cantrip intent [] initial-loom) :new-turns)))

(defn invoke
  "Creates a persistent entity handle for multi-cast sessions."
  [cantrip]
  (domain/validate-cantrip! cantrip)
  (let [entity-id (str (random-uuid))]
    {:entity-id entity-id
     :cantrip cantrip
     :status :ready
     :loom (atom (loom/new-loom (:call cantrip)))
     :turn-history (atom [])}))

(defn cast-intent
  "Runs one intent against an invoked entity, preserving state across casts."
  [entity intent]
  (domain/require-intent! intent)
  (let [cantrip (:cantrip entity)
        _ (domain/validate-cantrip! cantrip)
        prior-turns @(:turn-history entity)
        current-loom @(:loom entity)
        result (run-cast (:entity-id entity) cantrip intent prior-turns current-loom)]
    (swap! (:turn-history entity) into (:new-turns result))
    (reset! (:loom entity) (:loom result))
    (dissoc result :new-turns)))

(defn entity-state
  "Returns current persistent state snapshot for an invoked entity."
  [entity]
  {:entity-id (:entity-id entity)
   :status (:status entity)
   :turn-count (count @(:turn-history entity))
   :loom @(:loom entity)})
