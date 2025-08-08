1. Git clone
2. Look at local_script_*.sh
3. I have a working script that generate queries and post prepared statements output

1h00 hours

4. Next day I played with logs, remove too many building steps and try to understand the code and the flow of the request. No pressure. It's a game.
 https://github.com/postgres/postgres/blob/master/contrib/pg_stat_statements/pg_stat_statements.c#L1407


Third day. Timebox 1h or less.

5. I tried to look at hooks and where I could stay. I tried to add new columns, call directly pgss_store from the PG_CATCH before rethrown. And I probably continue this idea and then make it works and then ask for a first review outside of commit fest

6. I went back to simple column to store call initiated + I update scripts to build and run tests locally because I didn't contribute for months on this patch. Also add some cleaning mechanism when bad pg_ctl stop happpens.

7. I have a working version but that increment only for existing pgss entries. Now I'm working to create new entry if the query is failing for the first call. I lost some times because `hash_search(pgss_hash, &key, HASH_FIND, NULL)` was not finding the hash entry. It was because of missing padding. `memset(&key, 0, sizeof(pgssHashKey));` :D
