(ns cantrip.redaction-test
  (:require [clojure.test :refer [deftest is]]
            [cantrip.redaction :as redaction]))

(deftest redact-secrets-in-text
  (is (= "token [REDACTED]"
         (redaction/redact-text "token sk-proj-secret-123"))))

(deftest redact-secrets-in-structures
  (let [v {:message "api_key=ABC123"
           :nested [{:text "sk-foo"}]}]
    (is (= {:message "[REDACTED]"
            :nested [{:text "[REDACTED]"}]}
           (redaction/redact-value v)))))
