if [ -z "$PG_TEST_DIR" ]; then
    export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
fi

if [ -z "$PGPORT" ]; then
    export PGPORT=5433
fi

export DYLD_LIBRARY_PATH=$PG_TEST_DIR/lib:$DYLD_LIBRARY_PATH
export PATH=$PG_TEST_DIR/bin:$PATH

if ! $PG_TEST_DIR/bin/pg_ctl status -D $PG_TEST_DIR/data >/dev/null 2>&1; then
    echo "Starting PostgreSQL server..."
    $PG_TEST_DIR/bin/pg_ctl start -D $PG_TEST_DIR/data -l $PG_TEST_DIR/logfile
fi

# create if not exists
$PG_TEST_DIR/bin/createdb test 2>/dev/null || true
$PG_TEST_DIR/bin/psql test -c "DROP EXTENSION IF EXISTS pg_stat_statements;"
$PG_TEST_DIR/bin/psql test -c "CREATE EXTENSION pg_stat_statements;"

# Run ALTER SYSTEM commands separately to avoid transaction block issues
$PG_TEST_DIR/bin/psql test -c "ALTER SYSTEM SET log_min_messages = 'info';"
$PG_TEST_DIR/bin/psql test -c "ALTER SYSTEM SET client_min_messages = 'info';"

# Skip reload for now as it seems to hang with verbose logging
echo "Skipping pg_reload_conf() due to verbose logging - restart will pick up changes"

$PG_TEST_DIR/bin/psql test -c "SELECT extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"

$PG_TEST_DIR/bin/psql test -c "SELECT pg_stat_statements_reset();"
# Now run the query that will timeout
$PG_TEST_DIR/bin/psql test -c "ALTER DATABASE test SET statement_timeout = '2s';"
$PG_TEST_DIR/bin/psql test -c "SELECT pg_sleep(1), 'test';"
$PG_TEST_DIR/bin/psql test -c "ALTER DATABASE test SET statement_timeout = '1ms';"
$PG_TEST_DIR/bin/psql test -c "SELECT pg_sleep(1), 'test';"
$PG_TEST_DIR/bin/psql test -c "SELECT pg_sleep(1), 'test';"
$PG_TEST_DIR/bin/psql test -c "SELECT pg_sleep(1);" # We want to test that we can have only calls_aborted at 1 but calls at 0

$PG_TEST_DIR/bin/psql test -c "SELECT pg_stat_statements_reset();"
$PG_TEST_DIR/bin/psql test -c "DROP TABLE IF EXISTS t_dup, t_check;"
$PG_TEST_DIR/bin/psql test -c "CREATE TABLE t_dup(id int primary key);"
$PG_TEST_DIR/bin/psql test -c "INSERT INTO t_dup VALUES (1);"
$PG_TEST_DIR/bin/psql test -c "CREATE TABLE t_check(x int CHECK (x > 0));"
$PG_TEST_DIR/bin/psql test -c "SELECT 42;" # success entry
$PG_TEST_DIR/bin/psql test -c "INSERT INTO t_dup VALUES (1);" || true # unique violation
$PG_TEST_DIR/bin/psql test -c "INSERT INTO t_check VALUES (0);" || true # check violation

$PG_TEST_DIR/bin/psql -P pager=off test -c "
-- Check pg_stat_statements
SELECT query,
       calls,
       calls_aborted,
       total_exec_time,
       mean_exec_time,
       rows,
       shared_blks_hit,
       shared_blks_read,
       temp_blks_read,
       temp_blks_written
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
LIMIT 5;
"

echo "🦀 Test completed successfully!"
