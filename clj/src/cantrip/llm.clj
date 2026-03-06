(ns cantrip.llm
  (:require [clojure.data.json :as json]
            [clojure.string :as str])
  (:import [java.net URI]
           [java.net.http HttpClient HttpRequest HttpRequest$BodyPublishers HttpResponse$BodyHandlers]
           [java.time Duration]))

;; ---------------------------------------------------------------------------
;; Shared validation helpers
;; ---------------------------------------------------------------------------

(defn- tool-call-ids [tool-calls]
  (map :id tool-calls))

(defn- ensure-tool-calls-have-ids! [tool-calls]
  (doseq [call tool-calls]
    (when-not (string? (:id call))
      (throw (ex-info "tool calls must have unique IDs"
                      {:rule "LLM-4" :tool-call call}))))
  (let [ids (tool-call-ids tool-calls)
        unique-count (count (set ids))]
    (when-not (= unique-count (count ids))
      (throw (ex-info "duplicate tool call ID"
                      {:rule "LLM-4" :ids ids}))))
  tool-calls)

(defn- ensure-required-shape! [response]
  (when-not (or (string? (:content response))
                (seq (:tool-calls response)))
    (throw (ex-info "llm returned neither content nor tool_calls"
                    {:rule "LLM-3"})))
  response)

(defn- ensure-tool-choice-required! [response tool-choice]
  (when (and (= tool-choice :required)
             (empty? (:tool-calls response)))
    (throw (ex-info "tool_choice required but no tool calls returned"
                    {:rule "LLM-5"})))
  response)

(defn- ensure-tool-result-linkage! [response previous-tool-call-ids]
  (let [known-ids (set previous-tool-call-ids)
        tool-results (:tool-results response)]
    (doseq [tool-result tool-results]
      (when-not (contains? known-ids (:tool-call-id tool-result))
        (throw (ex-info "tool result without matching tool call"
                        {:rule "LLM-7"
                         :tool-result tool-result
                         :known-ids known-ids}))))
    response))

(defn- normalize-tool-call [call]
  {:id (:id call)
   :gate (or (:gate call) (:name call))
   :args (or (:args call) (:arguments call) {})})

(defn- normalize-response [response]
  (-> response
      (update :tool-calls #(mapv normalize-tool-call (or % [])))
      (update :tool-results #(vec (or % [])))))

(defn- validate-and-normalize [response tool-choice previous-tool-call-ids]
  (-> (normalize-response response)
      ensure-required-shape!
      (update :tool-calls #(do (ensure-tool-calls-have-ids! %) %))
      (ensure-tool-choice-required! tool-choice)
      (ensure-tool-result-linkage! previous-tool-call-ids)))

;; ---------------------------------------------------------------------------
;; Fake provider (existing behaviour)
;; ---------------------------------------------------------------------------

(defn- record-invocation!
  [llm invocation]
  (when (and (:record-inputs llm)
             (instance? clojure.lang.IAtom (:invocations llm)))
    (swap! (:invocations llm) conj invocation)))

(defn- response-index [llm turn-index]
  (if (and (:responses-by-invocation llm)
           (instance? clojure.lang.IAtom (:invocations llm)))
    (max 0 (dec (count @(:invocations llm))))
    turn-index))

(defn- query-fake
  [llm {:keys [turn-index messages tools tool-choice]}]
  (record-invocation! llm {:messages (vec messages)
                               :tools (vec tools)
                               :tool-choice tool-choice})
  (let [idx (response-index llm turn-index)
        responses (:responses llm)
        response (or (get responses idx)
                     (when (seq responses) (last responses))
                     {})]
    (when-let [err (:error response)]
      (throw (ex-info (or (:message err) "llm provider error")
                      {:status (:status err)
                       :provider-error err})))
    response))

;; ---------------------------------------------------------------------------
;; JSON encoder / decoder (via clojure.data.json)
;; ---------------------------------------------------------------------------

(defn- json-encode [v]
  (json/write-str v :key-fn #(if (keyword? %) (name %) (str %))))

(defn- json-decode [^String s]
  (json/read-str s))


;; ---------------------------------------------------------------------------
;; OpenAI-compatible provider
;; ---------------------------------------------------------------------------

(defn- openai-base-url [llm]
  (let [url (or (:base-url llm) (:base_url llm) "https://api.openai.com/v1")]
    (if (str/ends-with? url "/")
      (subs url 0 (dec (count url)))
      url)))

(defn- openai-api-key [llm]
  (or (:api-key llm)
      (:api_key llm)
      (System/getenv "OPENAI_API_KEY")))

(defn- openai-model [llm]
  (or (:model llm)
      (throw (ex-info "llm :model is required"
                      {:llm (dissoc llm :api-key :api_key)}))))

(defn- message->openai
  "Converts a cantrip message to OpenAI wire format."
  [msg]
  (let [role (name (:role msg))]
    (case role
      "system" {"role" "system" "content" (:content msg)}
      "user" {"role" "user" "content" (:content msg)}
      "assistant" (let [base {"role" "assistant"}
                        base (if (:content msg)
                               (assoc base "content" (:content msg))
                               base)
                        tool-calls (:tool-calls msg)]
                    (if (seq tool-calls)
                      (assoc base "tool_calls"
                             (mapv (fn [tc]
                                     {"id" (:id tc)
                                      "type" "function"
                                      "function" {"name" (let [g (or (:gate tc) (:name tc))]
                                                           (if (keyword? g) (name g) (str g)))
                                                  "arguments" (let [a (or (:args tc) (:arguments tc) {})]
                                                                (if (string? a) a (json-encode a)))}})
                                   tool-calls))
                      base))
      "tool" {"role" "tool"
              "tool_call_id" (or (:tool-call-id msg) (:tool_call_id msg) (:id msg) "")
              "content" (str (:content msg))}
      ;; fallback
      {"role" role "content" (str (:content msg))})))

(defn- tool->openai
  "Converts a cantrip tool definition to OpenAI function-calling format."
  [tool]
  (let [tool-name (or (:name tool) (when (keyword? tool) (name tool)) (str tool))
        desc (or (:description tool) "")
        params (or (:parameters tool) {})
        schema (cond-> (if (and (map? params) (or (contains? params "type") (contains? params :type)))
                         params
                         (merge {"type" "object"} params))
                 ;; OpenAI requires "properties" for object schemas
                 (not (or (contains? params "properties") (contains? params :properties)))
                 (assoc "properties" {}))]
    {"type" "function"
     "function" {"name" tool-name
                 "description" desc
                 "parameters" schema}}))

(defn- tool-choice->openai [tc]
  (cond
    (nil? tc) "auto"
    (= tc :auto) "auto"
    (= tc :none) "none"
    (= tc :required) "required"
    (string? tc) tc
    (keyword? tc) (name tc)
    :else "auto"))

(defn- build-openai-request-body [llm messages tools tool-choice]
  (let [body {"model" (openai-model llm)
              "messages" (mapv message->openai messages)
              "max_completion_tokens" (or (:max-tokens llm) (:max_tokens llm) 16384)}
        body (if (seq tools)
               (assoc body "tools" (mapv tool->openai tools))
               body)
        body (if (and (seq tools) tool-choice)
               (assoc body "tool_choice" (tool-choice->openai tool-choice))
               body)]
    body))

(defn- http-post
  "Makes an HTTP POST request using Java's built-in HttpClient."
  [url headers body-str timeout-ms]
  (let [client (-> (HttpClient/newBuilder)
                   (.connectTimeout (Duration/ofMillis (long (or timeout-ms 30000))))
                   (.build))
        builder (-> (HttpRequest/newBuilder)
                    (.uri (URI/create url))
                    (.timeout (Duration/ofMillis (long (or timeout-ms 60000))))
                    (.POST (HttpRequest$BodyPublishers/ofString body-str)))]
    (doseq [[k v] headers]
      (.header builder k v))
    (let [request (.build builder)
          response (.send client request (HttpResponse$BodyHandlers/ofString))]
      {:status (.statusCode response)
       :body (.body response)})))

(defn- parse-openai-tool-call [tc]
  (let [func (get tc "function")
        args-str (get func "arguments" "{}")]
    {:id (get tc "id")
     :gate (get func "name")
     :args (try (json-decode args-str)
                (catch Exception _ {}))}))

(defn- parse-openai-response
  "Parses an OpenAI chat completion response into cantrip's internal format."
  [body-str]
  (let [body (json-decode body-str)
        error (get body "error")]
    (when error
      (throw (ex-info (or (get error "message") "OpenAI API error")
                      {:status (get error "code")
                       :provider-error error})))
    (let [choices (get body "choices" [])
          choice (first choices)
          message (get choice "message" {})
          content (get message "content")
          openai-tool-calls (get message "tool_calls")
          usage-raw (get body "usage" {})
          tool-calls (when (seq openai-tool-calls)
                       (mapv parse-openai-tool-call openai-tool-calls))]
      (cond-> {:usage {:prompt_tokens (long (or (get usage-raw "prompt_tokens") 0))
                       :completion_tokens (long (or (get usage-raw "completion_tokens") 0))}}
        content (assoc :content content)
        (seq tool-calls) (assoc :tool-calls tool-calls)))))

(defn- query-openai
  "Queries an OpenAI-compatible API endpoint."
  [llm {:keys [messages tools tool-choice]}]
  (let [api-key (openai-api-key llm)
        _ (when (str/blank? api-key)
            (throw (ex-info "OpenAI API key is required. Set :api-key in llm or OPENAI_API_KEY env var."
                            {:rule "LLM-OPENAI-1"})))
        base-url (openai-base-url llm)
        url (str base-url "/chat/completions")
        request-body (build-openai-request-body llm messages tools tool-choice)
        body-json (json-encode request-body)
        timeout-ms (or (:timeout-ms llm) (:timeout_ms llm) 120000)
        headers {"Content-Type" "application/json"
                 "Authorization" (str "Bearer " api-key)}
        {:keys [status body]} (try
                                 (http-post url headers body-json timeout-ms)
                                 (catch Exception e
                                   (throw (ex-info (str "HTTP request to OpenAI failed: " (.getMessage e))
                                                   {:status 0
                                                    :provider-error {:message (.getMessage e)}}))))]
    (when (and (integer? status) (>= status 400))
      (let [err-body (try (json-decode body) (catch Exception _ nil))
            err-msg (or (get-in err-body ["error" "message"])
                        (str "OpenAI API returned HTTP " status))]
        (throw (ex-info err-msg
                        {:status status
                         :provider-error {:message err-msg
                                          :status status
                                          :body body}}))))
    (parse-openai-response body)))

;; ---------------------------------------------------------------------------
;; Public API  -- dispatch on :provider
;; ---------------------------------------------------------------------------

(defn query
  "Queries the configured llm. Dispatches on :provider --
   :fake (default) for deterministic scripted responses,
   :openai / :openai-compatible for real LLM API calls."
  [llm {:keys [turn-index messages tools tool-choice previous-tool-call-ids]
            :as params}]
  (let [provider (or (:provider llm) :fake)
        raw-response (case provider
                       :fake (query-fake llm params)
                       (:openai :openai-compatible) (query-openai llm params)
                       (throw (ex-info (str "unknown llm provider: " provider)
                                       {:provider provider})))
        ;; Skip tool_choice enforcement for :fake — real APIs enforce it server-side
        effective-tool-choice (if (= :fake provider) :auto tool-choice)]
    (validate-and-normalize raw-response effective-tool-choice previous-tool-call-ids)))
