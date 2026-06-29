#!/usr/bin/env bb
(ns run-coverage
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.string :as str]))

;; Directories
(def ebin-dir "build/dev/erlang/gleamunison/ebin")

;; Find all beam files in the ebin directory that we want to measure
(defn find-modules []
  (let [all-beams (map #(str (fs/file-name %)) (fs/glob ebin-dir "*.beam"))
        app-beams (filter
                   (fn [name]
                     (and
                      (or (str/starts-with? name "gleamunison@")
                          (str/starts-with? name "gleamunison_")
                          (= name "gleamunison.beam"))
                      (not (str/ends-with? name "_test.beam"))
                      (not (= name "gleamunison_ffi_test.beam"))
                      (not (= name "gleamunison_coverage_runner.beam"))
                      (not (= name "gleamunison_escript.beam"))))
                   all-beams)]
    (map #(str/replace % #"\.beam$" "") app-beams)))

(defn find-ebin-dirs []
  (let [dev-dir (fs/file "build/dev/erlang")]
    (->> (fs/list-dir dev-dir)
         (map #(fs/file % "ebin"))
         (filter fs/directory?)
         (map str))))

(defn generate-runner-source [modules]
  (let [module-atoms (str/join ", " (map #(str "'" % "'") modules))]
    (str
     "-module(gleamunison_coverage_runner).\n"
     "-export([main/0, main/1]).\n\n"
     "main() -> main([]).\n"
     "main(_) ->\n"
     "    cover:start(),\n"
     "    Modules = [" module-atoms "],\n"
     "    lists:foreach(fun(M) ->\n"
     "        case cover:compile_beam(code:which(M)) of\n"
     "            {ok, _} -> ok;\n"
     "            Err -> io:format(\"Failed to instrument ~p: ~p~n\", [M, Err])\n"
     "        end\n"
     "    end, Modules),\n"
     "    io:format(\"=== Running Tests ===~n\"),\n"
     "    TestBeams = filelib:wildcard(\"build/dev/erlang/gleamunison/ebin/*_test.beam\"),\n"
     "    TestModules = [list_to_atom(filename:basename(B, \".beam\")) || B <- TestBeams],\n"
     "    io:format(\"Running ~p unit tests...~n\", [length(TestModules)]),\n"
     "    eunit:test(TestModules),\n"
     "    Levels = dogfood:all_levels(),\n"
     "    lists:foreach(fun(N) ->\n"
     "        Key = list_to_binary(\"level\" ++ integer_to_list(N)),\n"
     "        case gleam@dict:get(Levels, Key) of\n"
     "            {ok, Fun} -> Fun();\n"
     "            _ -> ok\n"
     "        end\n"
     "    end, lists:seq(1, 1250)),\n"
     "    io:format(\"=== Analyzing Coverage ===~n\"),\n"
     "    Results = lists:map(fun(M) ->\n"
     "        case cover:analyze(M, coverage, module) of\n"
     "            {ok, {M, {Cov, NotCov}}} -> {M, Cov, NotCov};\n"
     "            Other -> io:format(\"M: ~p, result: ~p~n\", [M, Other]), {M, 0, 0}\n"
     "        end\n"
     "    end, Modules),\n"
     "    io:format(\"~-35s ~-10s ~-10s ~-10s~n\", [\"Module\", \"Covered\", \"Uncovered\", \"%\"]),\n"
     "    io:format(\"~70c~n\", [$-]),\n"
     "    {TotalCov, TotalNotCov} = lists:foldl(fun({M, Cov, NotCov}, {AccCov, AccNotCov}) ->\n"
     "        Total = Cov + NotCov,\n"
     "        Pct = case Total of 0 -> 100.0; _ -> (Cov * 100.0) / Total end,\n"
     "        io:format(\"~-35s ~-10w ~-10w ~-10.1f%~n\", [M, Cov, NotCov, Pct]),\n"
     "        if NotCov > 0 ->\n"
     "            {ok, Lines} = cover:analyze(M, coverage, line),\n"
     "            UncoveredLines = [L || {{_, L}, {0, 1}} <- Lines],\n"
     "            io:format(\"  Uncovered lines: ~w~n\", [lists:sort(UncoveredLines)]);\n"
     "           true -> ok\n"
     "        end,\n"
     "        {AccCov + Cov, AccNotCov + NotCov}\n"
     "    end, {0, 0}, Results),\n"
     "    io:format(\"~70c~n\", [$=]),\n"
     "    GrandTotal = TotalCov + TotalNotCov,\n"
     "    GrandPct = case GrandTotal of 0 -> 100.0; _ -> (TotalCov * 100.0) / GrandTotal end,\n"
     "    io:format(\"~-35s ~-10w ~-10w ~-10.1f%~n\", [\"TOTAL\", TotalCov, TotalNotCov, GrandPct]),\n"
     "    if TotalNotCov > 0 ->\n"
     "        io:format(\"~nCoverage is less than 100%!~n\"),\n"
     "        init:stop(1);\n"
     "       true ->\n"
     "        io:format(\"~n100% Code Coverage Achieved!~n\"),\n"
     "        init:stop(0)\n"
     "    end.\n")))

(defn -main []
  (println "=== Codebase Coverage Runner ===")
  (let [modules (find-modules)]
    (println (str "Found " (count modules) " modules to measure."))
    (spit "src/gleamunison_coverage_runner.erl" (generate-runner-source modules))
    (try
      ;; Compile the runner
      (let [comp-res (proc/shell {:out :string :err :string :continue true}
                                 "erlc" "-o" ebin-dir "src/gleamunison_coverage_runner.erl")]
        (if (not= 0 (:exit comp-res))
          (do
            (println "Failed to compile runner:")
            (println (:err comp-res))
            (System/exit 1))
          ;; Run the runner with all dependencies on the path
          (let [ebins (find-ebin-dirs)
                pa-args (mapcat (fn [p] ["-pa" p]) ebins)
                run-args (concat ["erl" "-noshell"]
                                 pa-args
                                 ["-run" "gleamunison_coverage_runner" "main"
                                  "-run" "init" "stop"])
                run-res (apply proc/shell {:out :inherit :err :inherit :continue true} run-args)]
            (System/exit (:exit run-res)))))
      (finally
        ;; Cleanup
        (fs/delete-if-exists "src/gleamunison_coverage_runner.erl")
        (fs/delete-if-exists (str ebin-dir "/gleamunison_coverage_runner.beam"))))))

(when (= *file* (System/getProperty "babashka.file")) (-main))
