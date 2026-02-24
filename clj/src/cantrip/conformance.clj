(ns cantrip.conformance
  (:require [cantrip.runtime :as runtime]
            [clojure.edn :as edn]
            [clojure.java.shell :as sh]
            [clojure.string :as str]))

(defn- load-test-cases []
  (let [{:keys [exit out err]} (sh/sh "ruby" "scripts/tests_yaml_to_edn.rb")]
    (when-not (zero? exit)
      (throw (ex-info "failed to load tests.yaml through bridge script"
                      {:exit exit :stderr err})))
    (edn/read-string out)))

(defn- case-by-rule [cases rule-id]
  (first (filter #(= rule-id (:rule %)) cases)))

(defn- normalize-setup [setup]
  (let [circle (:circle setup)]
    {:crystal (:crystal setup)
     :call (or (:call setup) {})
     :circle (if (map? circle)
               (assoc circle :medium (or (:medium circle) :conversation))
               circle)}))

(defn- run-cast-error-case! [tc]
  (let [setup (:setup tc)
        cantrip (normalize-setup setup)
        intent (get-in tc [:action :cast :intent])
        expected-error (get-in tc [:expect :error])]
    (try
      (runtime/cast cantrip intent)
      {:pass? false
       :message "expected cast to fail but it succeeded"}
      (catch clojure.lang.ExceptionInfo e
        (let [msg (.getMessage e)]
          {:pass? (if (string? expected-error)
                    (str/includes? msg expected-error)
                    true)
           :message (str "caught error: " msg)})))))

(defn- run-scaffold-case! [cases]
  (let [rule-id "INTENT-1"
        tc (case-by-rule cases rule-id)]
    (when-not tc
      (throw (ex-info "scaffold case missing from tests.yaml" {:rule rule-id})))
    (let [{:keys [pass? message]} (run-cast-error-case! tc)]
      (println (str "YAML scaffold: " rule-id " -> " (if pass? "PASS" "FAIL")))
      (println message)
      pass?)))

(defn -main [& _]
  (let [cases (load-test-cases)
        total (count cases)
        skipped-cases (filter :skip cases)
        skipped-rules (map :rule skipped-cases)
        skipped (count skipped-cases)
        runnable (- total skipped)
        pass? (run-scaffold-case! cases)]
    (println (str "Skipped rules: " (str/join ", " skipped-rules)))
    (println (str "YAML cases loaded: " total ", skipped: " skipped ", runnable: " runnable))
    (when-not pass?
      (System/exit 1))))
