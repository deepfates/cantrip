(require '[cantrip.runtime :as runtime])

(defn mk-terminal-child [answer]
  {:crystal {:provider :fake
             :responses [{:tool-calls [{:id "done_1"
                                        :gate :done
                                        :args {:answer answer}}]}]}
   :call {}
   :circle {:medium :code
            :gates [:done]
            :wards [{:max-turns 2}]}})

(defn mk-level-code [child-cantrip]
  (str "(submit-answer (call-agent {:cantrip "
       (pr-str child-cantrip)
       " :intent \"nested\"}))"))

(defn mk-nested-cantrip [levels]
  (loop [remaining levels
         child (mk-terminal-child "leaf")]
    (if (zero? remaining)
      child
      (recur (dec remaining)
             {:crystal {:provider :fake
                        :responses [{:content (mk-level-code child)}]}
              :call {:require-done-tool true}
              :circle {:medium :code
                       :gates [:done :call_agent]
                       :wards [{:max-turns 4} {:max-depth 12}]}}))))

(defn run-once [levels]
  (let [cantrip (mk-nested-cantrip levels)
        t0 (System/nanoTime)
        result (runtime/cast cantrip "perf")
        t1 (System/nanoTime)]
    {:duration-ms (double (/ (- t1 t0) 1000000.0))
     :status (:status result)
     :turns (count (:turns result))
     :result (:result result)}))

(defn stats [xs]
  (let [sorted (sort xs)
        n (count sorted)
        idx95 (max 0 (dec (int (Math/ceil (* 0.95 n)))))]
    {:min (first sorted)
     :median (nth sorted (quot n 2))
     :p95 (nth sorted idx95)
     :max (last sorted)}))

(defn run-benchmark [levels iterations]
  (let [runs (repeatedly iterations #(run-once levels))
        durations (map :duration-ms runs)]
    {:levels levels
     :iterations iterations
     :durations-ms (stats durations)
     :sample (first runs)}))

(let [levels (Long/parseLong (or (first *command-line-args*) "4"))
      iterations (Long/parseLong (or (second *command-line-args*) "20"))
      out (run-benchmark levels iterations)]
  (println (pr-str out)))
