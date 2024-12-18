1. Git clone
2. Look at local_script_*.sh
3. I have a working script that generate queries and post prepared statements output

1h00 hours

4. Next day I played with logs, remove too many building steps and try to understand the code and the flow of the request. No pressure. It's a game.
 https://github.com/postgres/postgres/blob/master/contrib/pg_stat_statements/pg_stat_statements.c#L1407


Third day. Timebox 1h or less.

5. I tried to look at hooks and where I could stay. I tried to add new columns, call directly pgss_store from the PG_CATCH before rethrown. And I probably continue this idea and then make it works and then ask for a first review outside of commit fest
