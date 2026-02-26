(ns cantrip.gates)

(defn gate-name
  "Returns a normalized string gate name from keyword/string/map gate specs."
  [gate]
  (cond
    (keyword? gate) (name gate)
    (string? gate) gate
    (map? gate) (gate-name (:name gate))
    :else (str gate)))

(defn gate-keyword
  "Returns normalized keyword gate id."
  [gate]
  (keyword (gate-name gate)))

(defn gate-names
  "Returns normalized gate names from map or sequential gate collections."
  [gates]
  (cond
    (map? gates) (mapv gate-name (keys gates))
    (sequential? gates) (mapv gate-name gates)
    :else []))

(defn gate-tools
  "Projects gate definitions into crystal tool metadata."
  [gates]
  (cond
    (map? gates) (mapv (fn [[k v]]
                         (merge {:name (gate-name k)}
                                (when (map? v)
                                  {:parameters (or (:parameters v) {})})))
                       gates)
    (sequential? gates) (mapv (fn [gate]
                                (cond
                                  (map? gate) {:name (gate-name gate)
                                               :parameters (or (:parameters gate) {})}
                                  :else {:name (gate-name gate)}))
                              gates)
    :else []))

(defn gate-available?
  "Checks whether a gate id is available in circle gate definitions."
  [gates gate]
  (let [gate-id (gate-keyword gate)]
    (cond
      (map? gates) (contains? gates gate-id)
      (sequential? gates) (boolean (some #(= gate-id (gate-keyword %)) gates))
      :else false)))
