# Initialize the database
# rm -rf $PG_TEST_DIR/data
# $PG_TEST_DIR/bin/initdb -D $PG_TEST_DIR/data

# Empty the logfile
rm -f $PG_TEST_DIR/logfile
# RM pid
rm -f $PG_TEST_DIR/data/postmaster.pid

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
$PG_TEST_DIR/bin/pg_ctl -D $PG_TEST_DIR/data -l $PG_TEST_DIR/logfile start
