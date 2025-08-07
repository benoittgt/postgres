# Initialize the database
# rm -rf $PG_TEST_DIR/data
# $PG_TEST_DIR/bin/initdb -D $PG_TEST_DIR/data

if [ -z "$PG_TEST_DIR" ]; then
    export PG_TEST_DIR=/Users/benoit.tigeot/projects/lifen/pg_test
fi

# Function to cleanup PostgreSQL processes and shared memory
cleanup_postgres() {
    echo "🧹 Cleaning up PostgreSQL processes and shared memory..."

    # Stop PostgreSQL gracefully
    $PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data stop -m immediate 2>/dev/null || true

    # Wait for graceful shutdown
    sleep 1

    # Force kill any remaining processes
    pkill -f "postgres.*$PG_TEST_DIR" 2>/dev/null || true
    pkill -f "postgres.*pg_test" 2>/dev/null || true
    
    # Kill any PostgreSQL processes running on port 5433
    lsof -ti:5433 | xargs kill -9 2>/dev/null || true
    
    # More specific cleanup - avoid killing system PostgreSQL
    pkill -f "postgres.*port.*5433" 2>/dev/null || true

    # Wait for processes to fully terminate
    sleep 1

    echo "🧹 Removing shared memory segments..."
    rm -f $PG_TEST_DIR/data/postmaster.pid 2>/dev/null || true

    # Remove all shared memory segments owned by current user
    for shmid in $(ipcs -m | awk -v user="`whoami`" '$3 == user {print $2}'); do
        echo "🧹 Removing shared memory segment: $shmid"
        ipcrm -m $shmid 2>/dev/null || true
    done

    # Clean up semaphores if any
    for semid in $(ipcs -s | awk -v user="`whoami`" '$3 == user {print $2}'); do
        echo "🧹 Removing semaphore: $semid"
        ipcrm -s $semid 2>/dev/null || true
    done

    echo "🧹 Cleanup complete!"
}

# Clean up any existing PostgreSQL processes and shared memory
cleanup_postgres

rm -f $PG_TEST_DIR/logfile

# Modify postgresql.conf to enable pg_stat_statements and set port
# check if already done
if grep -q "port = 5433" $PG_TEST_DIR/data/postgresql.conf; then
    echo "config already set"
else
    echo "config will be set"
    echo "port = 5433" >> $PG_TEST_DIR/data/postgresql.conf
    echo "shared_preload_libraries = 'pg_stat_statements'" >> $PG_TEST_DIR/data/postgresql.conf
    echo "pg_stat_statements.track = all" >> $PG_TEST_DIR/data/postgresql.conf
    echo "pg_stat_statements.max = 10000" >> $PG_TEST_DIR/data/postgresql.conf
    echo "
    # Logging verbosity
    log_min_messages = 'debug5'
    log_min_error_statement = 'debug5'
    log_min_duration_statement = 0  # Log all statements

    # What to log
    log_checkpoints = on
    log_connections = on
    log_disconnections = on
    log_duration = on
    log_error_verbosity = verbose
    log_lock_waits = on
    log_statement = 'all'
    log_replication_commands = on

    # Timing
    log_parser_stats = on
    log_planner_stats = on
    log_executor_stats = on

    # For development/debugging
    debug_print_parse = on
    debug_print_rewritten = on
    debug_print_plan = on
    debug_pretty_print = on
    " >> $PG_TEST_DIR/data/postgresql.conf
fi

# Seems to be required by pg_stat_statements
# mkdir -p $PG_TEST_DIR/data/pg_stat

# Start the database
echo "🦀 Starting PostgreSQL in $PG_TEST_DIR with logging at $PG_TEST_DIR/logfile"

$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data -o "-p 5433" -l $PG_TEST_DIR/logfile start
