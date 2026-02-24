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

(defn- supports-action? [tc]
  (let [action (:action tc)]
    (or (true? (:construct-cantrip action))
        (map? (:cast action)))))

(defn- supports-expectation? [tc]
  (let [expect (set (keys (:expect tc)))
        supported #{:error :result :terminated :truncated :turns}]
    (every? supported expect)))

(defn- evaluate-expectation [tc run-result error-msg]
  (let [expect (:expect tc)]
    (cond
      (:error expect) (and (string? error-msg)
                           (str/includes? error-msg (:error expect)))
      :else (and
             (if (contains? expect :result)
               (= (:result expect) (:result run-result))
               true)
             (if (contains? expect :terminated)
               (= (:terminated expect) (= :terminated (:status run-result)))
               true)
             (if (contains? expect :truncated)
               (= (:truncated expect) (= :truncated (:status run-result)))
               true)
             (if (contains? expect :turns)
               (= (:turns expect) (count (:turns run-result)))
               true)))))

(defn- run-supported-case! [tc]
  (let [setup (:setup tc)
        cantrip (normalize-setup setup)
        action (:action tc)]
    (try
      (let [run-result (cond
                         (true? (:construct-cantrip action)) (runtime/new-cantrip cantrip)
                         (map? (:cast action)) (runtime/cast cantrip (get-in action [:cast :intent]))
                         :else ::unsupported)
            pass? (if (= ::unsupported run-result)
                    false
                    (evaluate-expectation tc run-result nil))]
        {:status (if pass? :pass :fail)
         :rule (:rule tc)})
      (catch clojure.lang.ExceptionInfo e
        {:status (if (evaluate-expectation tc nil (.getMessage e)) :pass :fail)
         :rule (:rule tc)
         :error (.getMessage e)}))))

(defn- run-batch! [cases]
  (let [runnable (remove :skip cases)
        supported (filter #(and (supports-action? %) (supports-expectation? %)) runnable)
        unsupported (remove #(and (supports-action? %) (supports-expectation? %)) runnable)
        results (map run-supported-case! supported)
        passes (count (filter #(= :pass (:status %)) results))
        fails (count (filter #(= :fail (:status %)) results))]
    (println (str "Batch mode: supported=" (count supported)
                  ", unsupported=" (count unsupported)
                  ", pass=" passes
                  ", fail=" fails))
    (when (seq unsupported)
      (println (str "Unsupported example rule IDs: "
                    (str/join ", " (take 20 (map :rule unsupported))))))
    (when (pos? fails)
      (println (str "Failed example rule IDs: "
                    (str/join ", " (map :rule (filter #(= :fail (:status %)) results)))))
      (System/exit 1))))

(defn -main [& args]
  (let [cases (load-test-cases)
        total (count cases)
        skipped-cases (filter :skip cases)
        skipped-rules (map :rule skipped-cases)
        skipped (count skipped-cases)
        runnable (- total skipped)
        batch? (some #{"--batch"} args)
        pass? (if batch?
                true
                (run-scaffold-case! cases))]
    (println (str "Skipped rules: " (str/join ", " skipped-rules)))
    (println (str "YAML cases loaded: " total ", skipped: " skipped ", runnable: " runnable))
    (when batch?
      (run-batch! cases))
    (when-not pass?
      (System/exit 1))))
