(ns cantrip.medium
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]))

(defmulti capability-view
  "Returns medium capability description for crystal context assembly."
  (fn [circle _dependencies] (:medium circle)))

(defmulti execute-utterance
  "Executes one utterance in the configured medium."
  (fn [circle _utterance _dependencies] (:medium circle)))

(defmethod capability-view :conversation
  [circle _]
  {:medium :conversation
   :gates (gates/gate-names (:gates circle))})

(defmethod capability-view :code
  [circle _]
  {:medium :code
   :gates (gates/gate-names (:gates circle))
   :notes ["host-projected gates available in medium context"]})

(defmethod capability-view :minecraft
  [circle _]
  {:medium :minecraft
   :gates (gates/gate-names (:gates circle))
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
