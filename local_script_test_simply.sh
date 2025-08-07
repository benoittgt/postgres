if [ -z "$PG_TEST_DIR" ]; then
    export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
fi
export DYLD_LIBRARY_PATH=$PG_TEST_DIR/lib:$DYLD_LIBRARY_PATH
export PATH=$PG_TEST_DIR/bin:$PATH

if ! $PG_TEST_DIR/bin/pg_ctl status -D $PG_TEST_DIR/data >/dev/null 2>&1; then
    echo "Starting PostgreSQL server..."
    $PG_TEST_DIR/bin/pg_ctl start -D $PG_TEST_DIR/data -l $PG_TEST_DIR/logfile
fi

# create if not exists
$PG_TEST_DIR/bin/createdb -p 5433 test 2>/dev/null || true
$PG_TEST_DIR/bin/psql -p 5433 test -c "DROP EXTENSION IF EXISTS pg_stat_statements;"
$PG_TEST_DIR/bin/psql -p 5433 test -c "CREATE EXTENSION pg_stat_statements;"

# Run ALTER SYSTEM commands separately to avoid transaction block issues
$PG_TEST_DIR/bin/psql -p 5433 test -c "ALTER SYSTEM SET log_min_messages = 'info';"
$PG_TEST_DIR/bin/psql -p 5433 test -c "ALTER SYSTEM SET client_min_messages = 'info';"

$PG_TEST_DIR/bin/psql -p 5433 test -c "SET statement_timeout = '1s';
SELECT pg_stat_statements_reset();
SELECT pg_sleep(2), count(*) FROM test_table;
"

$PG_TEST_DIR/bin/psql -p 5433 -P pager=off test -c "
-- Check pg_stat_statements
SELECT query,
       calls,
       calls_initiated,
       total_exec_time,
       mean_exec_time,
       rows,
       shared_blks_hit,
       shared_blks_read,
       temp_blks_read,
       temp_blks_written
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY calls_initiated DESC
LIMIT 5;
"

echo "🦀 Test completed successfully!"
