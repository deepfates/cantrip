(ns cantrip.loom
  (:require [cantrip.redaction :as redaction]
            [clojure.string :as str]))

(defn new-loom
  [call]
  {:call call
   :turns []})

(defn append-turn
  "Appends a turn record. Returns updated loom and inserted turn."
  [loom turn]
  (let [sequence (inc (count (:turns loom)))
        id (or (:id turn) (str "turn_" sequence))
        parent-id (if (= sequence 1)
                    nil
                    (or (:parent-id turn)
                        (:id (last (:turns loom)))))
        stored (assoc turn
                      :id id
                      :sequence sequence
                      :parent-id parent-id)]
    [(update loom :turns conj stored) stored]))

(defn annotate-reward
  [loom turn-id reward]
  (update loom :turns
          (fn [turns]
            (mapv (fn [turn]
                    (if (= (:id turn) turn-id)
                      (assoc turn :reward reward)
                      turn))
                  turns))))

(defn turn-by-id
  [loom turn-id]
  (first (filter #(= (:id %) turn-id) (:turns loom))))

(defn extract-thread
  "Extracts root-to-turn path for linearized replay."
  [loom turn-id]
  (loop [cursor (turn-by-id loom turn-id)
         acc []]
    (if (nil? cursor)
      (vec (reverse acc))
      (recur (turn-by-id loom (:parent-id cursor))
             (conj acc cursor)))))

(defn export-jsonl
  "Exports loom turns as line-delimited EDN records.
   Redaction defaults to :default; pass {:redaction :none} to opt out."
  [loom & [{:keys [redaction] :or {redaction :default}}]]
  (->> (:turns loom)
       (map (fn [turn]
              (pr-str (if (= redaction :none)
                        turn
                        (redaction/redact-value turn)))))
       (str/join "\n")))
