(ns cantrip.protocol.acp
  (:require [cantrip.runtime :as runtime]
            [clojure.string :as str]))

(defn new-router [cantrip]
  {:cantrip cantrip
   :initialized? false
   :sessions {}
   :next-session-id 1})

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
        params (:params req)]
    (cond
      (= method "initialize")
      [(assoc router :initialized? true)
       (result-response id {:protocolVersion 1 :serverInfo {:name "cantrip-clj"}})
       []]

      (not (:initialized? router))
      [router (error-response id -32002 "server not initialized") []]

      (= method "session/new")
      (let [sid (new-session-id router)
            next-router (-> router
                            (update :next-session-id inc)
                            (assoc-in [:sessions sid] {:history []}))]
        [next-router
         (result-response id {:sessionId sid})
         []])

      (= method "session/prompt")
      (let [sid (:sessionId params)
            session (get-in router [:sessions sid])]
        (cond
          (nil? session)
          [router (error-response id -32004 "unknown session") []]

          :else
          (let [prompt-text (extract-prompt-text params)]
            (if (str/blank? (or prompt-text ""))
              [router (error-response id -32602 "prompt must contain a text content block") []]
              (let [history (conj (:history session) prompt-text)
                    intent (str/join "\n" history)
                    cast-result (runtime/cast (:cantrip router) intent)
                    text (or (:result cast-result) "")
                    next-router (assoc-in router [:sessions sid :history] history)]
                [next-router
                 (result-response id {:sessionId sid
                                      :output [{:type "text" :text text}]})
                 [(session-update sid text)]])))))

      :else
      [router (error-response id -32601 "method not found") []])))
