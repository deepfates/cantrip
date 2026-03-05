(ns cantrip.redaction
  (:require [clojure.string :as str]))

(def ^:private secret-patterns
  [#"sk-[A-Za-z0-9\-_]+"
   #"(?i)(api[_-]?key\s*[:=]\s*)[A-Za-z0-9\-_]+" ])

(defn redact-text [s]
  (if (string? s)
    (reduce (fn [acc re]
              (str/replace acc re "[REDACTED]"))
            s
            secret-patterns)
    s))

(defn redact-value [v]
  (cond
    (string? v) (redact-text v)
    (map? v) (into {} (map (fn [[k val]] [k (redact-value val)]) v))
    (sequential? v) (mapv redact-value v)
    :else v))
