(ns cantrip.loom-test
  (:require [clojure.test :refer [deftest is]]
            [clojure.string :as str]
            [cantrip.loom :as loom]))

(deftest appends-turns-with-ids-and-parents
  (let [l0 (loom/new-loom {:system-prompt "x"})
        [l1 t1] (loom/append-turn l0 {:utterance {:content "a"} :observation []})
        [l2 t2] (loom/append-turn l1 {:utterance {:content "b"} :observation []})]
    (is (= "turn_1" (:id t1)))
    (is (nil? (:parent-id t1)))
    (is (= "turn_2" (:id t2)))
    (is (= "turn_1" (:parent-id t2)))
    (is (= 2 (count (:turns l2))))))

(deftest reward-annotation-does-not-remove-turns
  (let [l0 (loom/new-loom {})
        [l1 t1] (loom/append-turn l0 {:utterance {} :observation []})
        l2 (loom/annotate-reward l1 (:id t1) 1.0)]
    (is (= 1 (count (:turns l2))))
    (is (= 1.0 (-> l2 :turns first :reward)))))

(deftest extract-thread-root-to-leaf
  (let [l0 (loom/new-loom {})
        [l1 _] (loom/append-turn l0 {:id "a" :utterance {} :observation []})
        [l2 _] (loom/append-turn l1 {:id "b" :utterance {} :observation []})
        [l3 _] (loom/append-turn l2 {:id "c" :utterance {} :observation []})
        thread (loom/extract-thread l3 "c")]
    (is (= ["a" "b" "c"] (mapv :id thread)))))

(deftest export-jsonl-redacts-by-default
  (let [l0 (loom/new-loom {})
        [l1 _] (loom/append-turn l0 {:utterance {:content "token sk-proj-secret"}
                                     :observation []})
        out (loom/export-jsonl l1)]
    (is (not (str/includes? out "sk-proj-secret")))
    (is (str/includes? out "[REDACTED]"))))

(deftest export-jsonl-allows-opt-out
  (let [l0 (loom/new-loom {})
        [l1 _] (loom/append-turn l0 {:utterance {:content "token sk-proj-secret"}
                                     :observation []})
        out (loom/export-jsonl l1 {:redaction :none})]
    (is (str/includes? out "sk-proj-secret"))))
