(ns cantrip.medium
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]
            [clojure.edn :as edn]
            [clojure.string :as str]))

(defmulti capability-view
  "Returns medium capability description for crystal context assembly."
  (fn [circle _dependencies] (:medium circle)))

(defmulti execute-utterance
  "Executes one utterance in the configured medium."
  (fn [circle _utterance _dependencies] (:medium circle)))

(defmulti snapshot-state
  "Captures medium-local state for persistent entities."
  (fn [circle _dependencies] (:medium circle)))

(defmulti restore-state
  "Restores medium-local state into dependencies and returns restored state."
  (fn [circle _state _dependencies] (:medium circle)))

(defmethod capability-view :conversation
  [circle _]
  {:medium :conversation
   :gates (gates/gate-names (:gates circle))})

(defmethod snapshot-state :conversation
  [_ _]
  {})

(defmethod restore-state :conversation
  [_ state _]
  (or state {}))

(defmethod capability-view :code
  [circle _]
  {:medium :code
   :gates (gates/gate-names (:gates circle))
   :notes ["host-projected gates available in medium context"]})

(defmethod snapshot-state :code
  [_ _]
  {})

(defmethod restore-state :code
  [_ state _]
  (or state {}))

(defmethod capability-view :minecraft
  [circle _]
  {:medium :minecraft
   :gates (gates/gate-names (:gates circle))
   :notes ["world-facing medium via dependency context"]})

(defmethod snapshot-state :minecraft
  [_ _]
  {})

(defmethod restore-state :minecraft
  [_ state _]
  (or state {}))

(defmethod execute-utterance :conversation
  [circle utterance _]
  (circle/execute-tool-calls circle (vec (:tool-calls utterance))))

(defmethod execute-utterance :code
  [circle utterance _]
  (let [tool-calls (vec (:tool-calls utterance))
        code (:content utterance)
        parsed-call (when (and (empty? tool-calls)
                               (string? code)
                               (or (str/starts-with? (str/trim code) "(submit_answer")
                                   (str/starts-with? (str/trim code) "(submit-answer")))
                      (try
                        (let [form (edn/read-string code)
                              answer (second form)]
                          [{:id "code_done_1"
                            :gate :done
                            :args {:answer (str answer)}}])
                        (catch Exception _
                          nil)))]
    (circle/execute-tool-calls circle (or parsed-call tool-calls))))

(defmethod execute-utterance :minecraft
  [circle utterance _]
  ;; Placeholder: minecraft-medium specific execution will be implemented in M9.
  (circle/execute-tool-calls circle (vec (:tool-calls utterance))))
