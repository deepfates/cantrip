(ns cantrip.medium
  (:require [cantrip.circle :as circle]
            [cantrip.gates :as gates]
            [sci.core :as sci]))

(defn- eval-script->tool-calls
  [code bindings]
  (let [emitted (atom [])
        next-id (fn [] (str "code_call_" (inc (count @emitted))))
        emit! (fn [gate args]
                (swap! emitted conj {:id (next-id)
                                     :gate gate
                                     :args (or args {})}))
        submit! (fn [answer]
                  (emit! :done {:answer (str answer)}))
        call-gate! (fn
                     ([gate] (emit! gate {}))
                     ([gate args] (emit! gate args)))
        base-bindings {'submit-answer submit!
                       'submit_answer submit!
                       'call-gate call-gate!
                       'call_gate call-gate!}]
    (sci/eval-string code {:bindings (merge base-bindings bindings)})
    @emitted))

(defn- maybe-resolve
  [sym]
  (try
    (require 'lambdaisland.witchcraft)
    (ns-resolve 'lambdaisland.witchcraft sym)
    (catch Throwable _
      nil)))

(defn- minecraft-bindings
  [deps]
  (let [player-fn (or (:player-fn deps) (maybe-resolve 'player))
        xyz-fn (or (:xyz-fn deps) (maybe-resolve 'xyz))
        block-fn (or (:block-fn deps) (maybe-resolve 'block))
        set-block-fn (or (:set-block-fn deps) (maybe-resolve 'set-block))
        allow-mutation? (true? (:allow-mutation? deps))]
    (merge
     (when player-fn
       {'player (fn [] (player-fn))})
     (when xyz-fn
       {'xyz (fn [] (xyz-fn))})
     (when block-fn
       {'block (fn
                 ([loc] (block-fn loc))
                 ([] (block-fn)))})
     (when set-block-fn
       {'set-block (fn [loc b]
                     (if allow-mutation?
                       (set-block-fn loc b)
                       (throw (ex-info "minecraft mutation not allowed"
                                       {:mutation :set-block}))))}))))

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
  [circle utterance dependencies]
  (circle/execute-tool-calls circle (vec (:tool-calls utterance)) dependencies))

(defmethod execute-utterance :code
  [circle utterance dependencies]
  (let [tool-calls (vec (:tool-calls utterance))
        code (:content utterance)]
    (if (and (empty? tool-calls) (string? code))
      (try
        (circle/execute-tool-calls circle (eval-script->tool-calls code {}) dependencies)
        (catch Exception e
          {:observation [{:gate "code"
                          :arguments "{}"
                          :result (str "code execution error: " (.getMessage e))
                          :is-error true}]
           :terminated? false
           :result nil}))
      (circle/execute-tool-calls circle tool-calls dependencies))))

(defmethod execute-utterance :minecraft
  [circle utterance dependencies]
  (let [tool-calls (vec (:tool-calls utterance))
        code (:content utterance)]
    (if (and (empty? tool-calls) (string? code))
      (try
        (circle/execute-tool-calls circle
                                   (eval-script->tool-calls code
                                                            (minecraft-bindings dependencies))
                                   dependencies)
        (catch Exception e
          {:observation [{:gate "minecraft"
                          :arguments "{}"
                          :result (str "minecraft execution error: " (.getMessage e))
                          :is-error true}]
           :terminated? false
           :result nil}))
      (circle/execute-tool-calls circle tool-calls dependencies))))
