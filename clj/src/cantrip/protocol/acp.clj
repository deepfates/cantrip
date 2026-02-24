(ns cantrip.protocol.acp
  (:require [cantrip.redaction :as redaction]
            [cantrip.runtime :as runtime]
            [clojure.string :as str]))

(defn new-router
  ([cantrip]
   (new-router cantrip {}))
  ([cantrip {:keys [debug-mode]}]
   {:cantrip cantrip
    :initialized? false
    :sessions {}
    :next-session-id 1
    :debug-mode (true? debug-mode)
    :debug-events []}))

(defn router-health
  "Returns operational state for stdio health/idle reporting."
  [router]
  {:healthy? true
   :idle? true
   :initialized? (:initialized? router)
   :session-count (count (:sessions router))
   :debug-mode (:debug-mode router)})

(defn- error-response [id code message]
  {:jsonrpc "2.0"
   :id id
   :error {:code code :message message}})

(defn- result-response [id result]
  {:jsonrpc "2.0"
   :id id
   :result result})

(defn- extract-prompt-text [params]
  (let [prompt (:prompt params)
        content (:content params)]
    (cond
      (string? prompt) prompt
      (string? content) content
      (map? prompt)
      (let [pc (:content prompt)]
        (or (:text prompt)
            (when (string? pc) pc)
            (when (sequential? pc) (some :text pc))
            (some :text (:messages prompt))))
      (sequential? prompt) (some :text prompt)
      :else nil)))

(defn- new-session-id [router]
  (str "sess_" (:next-session-id router)))

(defn- session-update [session-id text]
  {:jsonrpc "2.0"
   :method "session/update"
   :params {:sessionId session-id
            :text text}})

(defn handle-request
  "Returns [updated-router response notifications]."
  [router req]
  (let [id (:id req)
        method (:method req)
        params (:params req)
        respond (fn [next-router response notifications outcome]
                  (let [event {:method method
                               :request-id id
                               :outcome outcome}
                        routed (if (:debug-mode next-router)
                                 (update next-router :debug-events conj event)
                                 next-router)]
                    [routed response notifications]))]
    (cond
      (= method "initialize")
      (respond (assoc router :initialized? true)
               (result-response id {:protocolVersion 1
                                    :serverInfo {:name "cantrip-clj"}})
               []
               :ok)

      (not (:initialized? router))
      (respond router
               (error-response id -32002 "server not initialized")
               []
               :error)

      (= method "session/new")
      (let [sid (new-session-id router)
            entity (runtime/invoke (:cantrip router))
            next-router (-> router
                            (update :next-session-id inc)
                            (assoc-in [:sessions sid] {:history []
                                                       :entity entity}))]
        (respond next-router
                 (result-response id {:sessionId sid})
                 []
                 :ok))

      (= method "session/prompt")
      (let [sid (:sessionId params)
            session (get-in router [:sessions sid])]
        (if (nil? session)
          (respond router
                   (error-response id -32004 "unknown session")
                   []
                   :error)
          (let [prompt-text (extract-prompt-text params)]
            (if (str/blank? (or prompt-text ""))
              (respond router
                       (error-response id -32602 "prompt must contain a text content block")
                       []
                       :error)
              (let [history (conj (:history session) prompt-text)
                    cast-result (runtime/cast-intent (:entity session) prompt-text)
                    text (or (:result cast-result) "")
                    redacted (redaction/redact-text text)
                    next-router (assoc-in router [:sessions sid :history] history)]
                (respond next-router
                         (result-response id {:sessionId sid
                                              :output [{:type "text"
                                                        :text redacted}]})
                         [(session-update sid redacted)]
                         :ok))))))

      :else
      (respond router
               (error-response id -32601 "method not found")
               []
               :error))))
