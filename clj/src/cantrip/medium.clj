(ns cantrip.medium
  (:require [cantrip.circle :as circle]))

(defn- gate-names [circle]
  (let [gates (:gates circle)]
    (cond
      (map? gates) (mapv name (keys gates))
      (sequential? gates) (mapv (fn [gate]
                                  (cond
                                    (keyword? gate) (name gate)
                                    (string? gate) gate
                                    (map? gate) (name (:name gate))
                                    :else (str gate)))
                                gates)
      :else [])))

(defmulti capability-view
  "Returns medium capability description for crystal context assembly."
  (fn [circle _dependencies] (:medium circle)))

(defmulti execute-utterance
  "Executes one utterance in the configured medium."
  (fn [circle _utterance _dependencies] (:medium circle)))

(defmethod capability-view :conversation
  [circle _]
  {:medium :conversation
   :gates (gate-names circle)})

(defmethod capability-view :code
  [circle _]
  {:medium :code
   :gates (gate-names circle)
   :notes ["host-projected gates available in medium context"]})

(defmethod capability-view :minecraft
  [circle _]
  {:medium :minecraft
   :gates (gate-names circle)
   :notes ["world-facing medium via dependency context"]})

(defmethod execute-utterance :conversation
  [circle utterance _]
  (circle/execute-tool-calls circle (vec (:tool-calls utterance))))

(defmethod execute-utterance :code
  [circle utterance _]
  ;; Placeholder: code-medium specific execution will be implemented in M7.
  (circle/execute-tool-calls circle (vec (:tool-calls utterance))))

(defmethod execute-utterance :minecraft
  [circle utterance _]
  ;; Placeholder: minecraft-medium specific execution will be implemented in M9.
  (circle/execute-tool-calls circle (vec (:tool-calls utterance))))
