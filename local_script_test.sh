export DYLD_LIBRARY_PATH=$PG_TEST_DIR/lib:$DYLD_LIBRARY_PATH
export PATH=$PG_TEST_DIR/bin:$PATH

$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data -l $PG_TEST_DIR/logfile restart

# create if not exists
$PG_TEST_DIR/bin/createdb -p 5433 test
$PG_TEST_DIR/bin/psql -p 5433 test -c "DROP EXTENSION pg_stat_statements;"
$PG_TEST_DIR/bin/psql -p 5433 test -c "CREATE EXTENSION pg_stat_statements;"

$PG_TEST_DIR/bin/psql -p 5433 test -c "
ALTER SYSTEM SET log_min_messages = 'info';
ALTER SYSTEM SET client_min_messages = 'info';
"
$PG_TEST_DIR/bin/psql -p 5433 test -c "SELECT extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"


$PG_TEST_DIR/bin/psql -p 5433 test -c "
DROP TABLE IF EXISTS test_table;
CREATE TABLE test_table (
    id serial PRIMARY KEY,
    data text
);
INSERT INTO test_table (data)
SELECT 'data_' || generate_series(1,1000);

SET statement_timeout = '1s';

SELECT pg_stat_statements_reset();

-- Two working queries
SELECT count(*) FROM test_table;
SELECT data FROM test_table WHERE id = 42;

-- One query that will timeout
SELECT pg_sleep(2), count(*) FROM test_table;
"

$PG_TEST_DIR/bin/psql -p 5433 test -c "
-- Check pg_stat_statements
SELECT query,
       calls,
       total_exec_time,
       mean_exec_time,
       rows,
       shared_blks_hit,
       shared_blks_read,
       temp_blks_read,
       temp_blks_written
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;
"
