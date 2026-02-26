<<<<<<< HEAD
(ns cantrip.crystal)
=======
(ns cantrip.crystal
  (:require [clojure.string :as str])
  (:import [java.net URI]
           [java.net.http HttpClient HttpRequest HttpRequest$BodyPublishers HttpResponse$BodyHandlers]
           [java.time Duration]))

;; ---------------------------------------------------------------------------
;; Shared validation helpers
;; ---------------------------------------------------------------------------
>>>>>>> monorepo/main

(defn- tool-call-ids [tool-calls]
  (map :id tool-calls))

(defn- ensure-tool-calls-have-ids! [tool-calls]
  (doseq [call tool-calls]
    (when-not (string? (:id call))
      (throw (ex-info "tool calls must have unique IDs"
                      {:rule "CRYSTAL-4" :tool-call call}))))
  (let [ids (tool-call-ids tool-calls)
        unique-count (count (set ids))]
    (when-not (= unique-count (count ids))
      (throw (ex-info "duplicate tool call ID"
                      {:rule "CRYSTAL-4" :ids ids}))))
  tool-calls)

(defn- ensure-required-shape! [response]
  (when-not (or (string? (:content response))
                (seq (:tool-calls response)))
    (throw (ex-info "crystal returned neither content nor tool_calls"
                    {:rule "CRYSTAL-3"})))
  response)

(defn- ensure-tool-choice-required! [response tool-choice]
  (when (and (= tool-choice :required)
             (empty? (:tool-calls response)))
    (throw (ex-info "tool_choice required but no tool calls returned"
                    {:rule "CRYSTAL-5"})))
  response)

(defn- ensure-tool-result-linkage! [response previous-tool-call-ids]
  (let [known-ids (set previous-tool-call-ids)
        tool-results (:tool-results response)]
    (doseq [tool-result tool-results]
      (when-not (contains? known-ids (:tool-call-id tool-result))
        (throw (ex-info "tool result without matching tool call"
                        {:rule "CRYSTAL-7"
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

<<<<<<< HEAD
=======
(defn- validate-and-normalize [response tool-choice previous-tool-call-ids]
  (-> (normalize-response response)
      ensure-required-shape!
      (update :tool-calls #(do (ensure-tool-calls-have-ids! %) %))
      (ensure-tool-choice-required! tool-choice)
      (ensure-tool-result-linkage! previous-tool-call-ids)))

;; ---------------------------------------------------------------------------
;; Fake provider (existing behaviour)
;; ---------------------------------------------------------------------------

>>>>>>> monorepo/main
(defn- record-invocation!
  [crystal invocation]
  (when (and (:record-inputs crystal)
             (instance? clojure.lang.IAtom (:invocations crystal)))
    (swap! (:invocations crystal) conj invocation)))

(defn- response-index [crystal turn-index]
  (if (and (:responses-by-invocation crystal)
           (instance? clojure.lang.IAtom (:invocations crystal)))
    (max 0 (dec (count @(:invocations crystal))))
    turn-index))

<<<<<<< HEAD
(defn query
  "Queries the configured crystal. For now supports deterministic fake responses."
  [crystal {:keys [turn-index messages tools tool-choice previous-tool-call-ids]}]
=======
(defn- query-fake
  [crystal {:keys [turn-index messages tools tool-choice]}]
>>>>>>> monorepo/main
  (record-invocation! crystal {:messages (vec messages)
                               :tools (vec tools)
                               :tool-choice tool-choice})
  (let [idx (response-index crystal turn-index)
        responses (:responses crystal)
        response (or (get responses idx)
                     (when (seq responses) (last responses))
<<<<<<< HEAD
                     {})
        _ (when-let [err (:error response)]
            (throw (ex-info (or (:message err) "crystal provider error")
                            {:status (:status err)
                             :provider-error err})))
        normalized (normalize-response response)]
    (-> normalized
        ensure-required-shape!
        (update :tool-calls #(do (ensure-tool-calls-have-ids! %) %))
        (ensure-tool-choice-required! tool-choice)
        (ensure-tool-result-linkage! previous-tool-call-ids))))
=======
                     {})]
    (when-let [err (:error response)]
      (throw (ex-info (or (:message err) "crystal provider error")
                      {:status (:status err)
                       :provider-error err})))
    response))

;; ---------------------------------------------------------------------------
;; Minimal JSON encoder / decoder (no external deps)
;; ---------------------------------------------------------------------------

(declare json-encode)

(defn- json-encode-string [^String s]
  (let [sb (StringBuilder. "\"")]
    (doseq [^char c s]
      (case c
        \" (.append sb "\\\"")
        \\ (.append sb "\\\\")
        \newline (.append sb "\\n")
        \return (.append sb "\\r")
        \tab (.append sb "\\t")
        \backspace (.append sb "\\b")
        \formfeed (.append sb "\\f")
        (if (< (int c) 0x20)
          (.append sb (format "\\u%04x" (int c)))
          (.append sb c))))
    (.append sb "\"")
    (str sb)))

(defn- json-encode [v]
  (cond
    (nil? v) "null"
    (true? v) "true"
    (false? v) "false"
    (integer? v) (str (long v))
    (number? v) (str (double v))
    (string? v) (json-encode-string v)
    (keyword? v) (json-encode-string (name v))
    (symbol? v) (json-encode-string (str v))
    (map? v) (str "{"
                  (str/join ","
                            (map (fn [[k val]]
                                   (let [key-str (cond (keyword? k) (name k)
                                                       (string? k) k
                                                       :else (str k))]
                                     (str (json-encode-string key-str) ":" (json-encode val))))
                                 v))
                  "}")
    (sequential? v) (str "[" (str/join "," (map json-encode v)) "]")
    :else (json-encode-string (str v))))

;; Minimal recursive-descent JSON parser
(defn- json-skip-ws [^String s ^long i]
  (loop [i i]
    (if (and (< i (.length s))
             (let [c (.charAt s i)]
               (or (= c \space) (= c \tab) (= c \newline) (= c \return))))
      (recur (inc i))
      i)))

(declare json-parse-value)

(defn- json-parse-string [^String s ^long i]
  ;; i points at opening "
  (let [sb (StringBuilder.)
        len (.length s)]
    (loop [j (inc i)]
      (when (>= j len)
        (throw (ex-info "unterminated JSON string" {:pos i})))
      (let [c (.charAt s j)]
        (cond
          (= c \")
          [(str sb) (inc j)]

          (= c \\)
          (let [next-j (inc j)]
            (when (>= next-j len)
              (throw (ex-info "unterminated JSON escape" {:pos j})))
            (let [esc (.charAt s next-j)]
              (case esc
                \" (do (.append sb \") (recur (inc next-j)))
                \\ (do (.append sb \\) (recur (inc next-j)))
                \/ (do (.append sb \/) (recur (inc next-j)))
                \n (do (.append sb \newline) (recur (inc next-j)))
                \r (do (.append sb \return) (recur (inc next-j)))
                \t (do (.append sb \tab) (recur (inc next-j)))
                \b (do (.append sb \backspace) (recur (inc next-j)))
                \f (do (.append sb \formfeed) (recur (inc next-j)))
                \u (let [hex (subs s (inc next-j) (+ next-j 5))
                         cp (Integer/parseInt hex 16)]
                     (.append sb (char cp))
                     (recur (+ next-j 5)))
                (do (.append sb esc) (recur (inc next-j))))))

          :else
          (do (.append sb c)
              (recur (inc j))))))))

(defn- json-parse-number [^String s ^long i]
  (let [len (.length s)]
    (loop [j i has-dot false]
      (if (and (< j len)
               (let [c (.charAt s j)]
                 (or (Character/isDigit c) (= c \.) (= c \-) (= c \+) (= c \e) (= c \E))))
        (recur (inc j) (or has-dot (= (.charAt s j) \.)))
        (let [num-str (subs s i j)]
          (if has-dot
            [(Double/parseDouble num-str) j]
            [(Long/parseLong num-str) j]))))))

(defn- json-parse-array [^String s ^long i]
  ;; i points at [
  (let [len (.length s)]
    (loop [j (json-skip-ws s (inc i))
           acc []]
      (when (>= j len)
        (throw (ex-info "unterminated JSON array" {:pos i})))
      (if (= (.charAt s j) \])
        [acc (inc j)]
        (let [[val next-j] (json-parse-value s j)
              next-j (json-skip-ws s next-j)]
          (when (>= next-j len)
            (throw (ex-info "unterminated JSON array" {:pos i})))
          (if (= (.charAt s next-j) \,)
            (recur (json-skip-ws s (inc next-j)) (conj acc val))
            (recur next-j (conj acc val))))))))

(defn- json-parse-object [^String s ^long i]
  ;; i points at {
  (let [len (.length s)]
    (loop [j (json-skip-ws s (inc i))
           acc {}]
      (when (>= j len)
        (throw (ex-info "unterminated JSON object" {:pos i})))
      (if (= (.charAt s j) \})
        [acc (inc j)]
        (let [_ (when-not (= (.charAt s j) \")
                  (throw (ex-info "expected string key in JSON object" {:pos j})))
              [k next-j] (json-parse-string s j)
              next-j (json-skip-ws s next-j)
              _ (when (or (>= next-j len) (not= (.charAt s next-j) \:))
                  (throw (ex-info "expected : in JSON object" {:pos next-j})))
              next-j (json-skip-ws s (inc next-j))
              [v next-j] (json-parse-value s next-j)
              next-j (json-skip-ws s next-j)]
          (when (>= next-j len)
            (throw (ex-info "unterminated JSON object" {:pos i})))
          (if (= (.charAt s next-j) \,)
            (recur (json-skip-ws s (inc next-j)) (assoc acc k v))
            (recur next-j (assoc acc k v))))))))

(defn- json-parse-value [^String s ^long i]
  (let [i (json-skip-ws s i)
        len (.length s)]
    (when (>= i len)
      (throw (ex-info "unexpected end of JSON" {:pos i})))
    (let [c (.charAt s i)]
      (cond
        (= c \") (json-parse-string s i)
        (= c \{) (json-parse-object s i)
        (= c \[) (json-parse-array s i)
        (= c \t) (if (and (<= (+ i 4) len) (= (subs s i (+ i 4)) "true"))
                   [true (+ i 4)]
                   (throw (ex-info "invalid JSON token" {:pos i})))
        (= c \f) (if (and (<= (+ i 5) len) (= (subs s i (+ i 5)) "false"))
                   [false (+ i 5)]
                   (throw (ex-info "invalid JSON token" {:pos i})))
        (= c \n) (if (and (<= (+ i 4) len) (= (subs s i (+ i 4)) "null"))
                   [nil (+ i 4)]
                   (throw (ex-info "invalid JSON token" {:pos i})))
        (or (Character/isDigit c) (= c \-))
        (json-parse-number s i)
        :else (throw (ex-info (str "unexpected JSON character: " c) {:pos i :char c}))))))

(defn- json-decode [^String s]
  (let [[v _] (json-parse-value s 0)]
    v))

;; ---------------------------------------------------------------------------
;; OpenAI-compatible provider
;; ---------------------------------------------------------------------------

(defn- openai-base-url [crystal]
  (let [url (or (:base-url crystal) (:base_url crystal) "https://api.openai.com/v1")]
    (if (str/ends-with? url "/")
      (subs url 0 (dec (count url)))
      url)))

(defn- openai-api-key [crystal]
  (or (:api-key crystal)
      (:api_key crystal)
      (System/getenv "OPENAI_API_KEY")))

(defn- openai-model [crystal]
  (or (:model crystal) "gpt-4o-mini"))

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
        params (or (:parameters tool) {})
        schema (if (and (map? params) (contains? params "type"))
                 params
                 (merge {"type" "object"} params))]
    {"type" "function"
     "function" {"name" tool-name
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

(defn- build-openai-request-body [crystal messages tools tool-choice]
  (let [body {"model" (openai-model crystal)
              "messages" (mapv message->openai messages)}
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
  [crystal {:keys [messages tools tool-choice]}]
  (let [api-key (openai-api-key crystal)
        _ (when (str/blank? api-key)
            (throw (ex-info "OpenAI API key is required. Set :api-key in crystal or OPENAI_API_KEY env var."
                            {:rule "CRYSTAL-OPENAI-1"})))
        base-url (openai-base-url crystal)
        url (str base-url "/chat/completions")
        request-body (build-openai-request-body crystal messages tools tool-choice)
        body-json (json-encode request-body)
        timeout-ms (or (:timeout-ms crystal) (:timeout_ms crystal) 60000)
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
  "Queries the configured crystal. Dispatches on :provider --
   :fake (default) for deterministic scripted responses,
   :openai / :openai-compatible for real LLM API calls."
  [crystal {:keys [turn-index messages tools tool-choice previous-tool-call-ids]
            :as params}]
  (let [provider (or (:provider crystal) :fake)
        raw-response (case provider
                       :fake (query-fake crystal params)
                       (:openai :openai-compatible) (query-openai crystal params)
                       (throw (ex-info (str "unknown crystal provider: " provider)
                                       {:provider provider})))]
    (validate-and-normalize raw-response tool-choice previous-tool-call-ids)))
>>>>>>> monorepo/main
