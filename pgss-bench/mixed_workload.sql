\set aid random(1, 100000 * :scale)
\set bid random(1, 1 * :scale)
\set tid random(1, 10 * :scale)
\set qtype random(1, 10)
\if :qtype = 1
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
\elif :qtype = 2
SELECT count(*) FROM pgbench_accounts WHERE aid BETWEEN :aid AND :aid + 100;
\elif :qtype = 3
SELECT tbalance FROM pgbench_tellers WHERE tid = :tid;
\elif :qtype = 4
SELECT bbalance FROM pgbench_branches WHERE bid = :bid;
\elif :qtype = 5
SELECT a.abalance FROM pgbench_accounts a JOIN pgbench_branches b ON a.bid = b.bid WHERE a.aid = :aid;
\elif :qtype = 6
SELECT sum(abalance) FROM pgbench_accounts WHERE bid = :bid;
\elif :qtype = 7
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = :aid;
\elif :qtype = 8
INSERT INTO pgbench_history (tid, bid, aid, delta) VALUES (:tid, :bid, :aid, 1);
\elif :qtype = 9
SELECT aid, abalance FROM pgbench_accounts WHERE bid = :bid LIMIT 10;
\else
SELECT abalance FROM pgbench_accounts WHERE bid = (SELECT bid FROM pgbench_tellers WHERE tid = :tid);
\endif
