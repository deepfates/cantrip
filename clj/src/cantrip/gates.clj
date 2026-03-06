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

(def ^:private done-parameters
  "Default schema for the done gate so LLMs know answer is required."
  {:type "object"
   :properties {:answer {:type "string" :description "Your final answer"}}
   :required ["answer"]})

(defn- default-parameters [gate-id]
  (if (= "done" gate-id) done-parameters {}))

(defn gate-tools
  "Projects gate definitions into llm tool metadata."
  [gates]
  (cond
    (map? gates) (mapv (fn [[k v]]
                         (let [gname (gate-name k)]
                           {:name gname
                            :parameters (if (map? v)
                                          (or (:parameters v) (default-parameters gname))
                                          (default-parameters gname))}))
                       gates)
    (sequential? gates) (mapv (fn [gate]
                                (let [gname (gate-name gate)]
                                  (if (map? gate)
                                    {:name gname
                                     :parameters (or (:parameters gate) (default-parameters gname))}
                                    {:name gname
                                     :parameters (default-parameters gname)})))
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
