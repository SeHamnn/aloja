# TPC-H benchmark from Todor Ivanov https://github.com/t-ivanov/D2F-Bench/
# Hive version
# Benchmark to test Hive installation and configurations

source_file "$ALOJA_REPO_PATH/shell/common/common_TPC-H.sh"
source_file "$ALOJA_REPO_PATH/shell/common/common_drill.sh"
set_drill_requires
source_file "$ALOJA_REPO_PATH/shell/common/common_zookeeper.sh"
set_zookeeper_requires


benchmark_suite_run() {
  logger "INFO: Running $BENCH_SUITE"
  initialize_drill_vars
  prepare_drill_config "$NET" "$DISK" "$BENCH_SUITE"
  
  tpc-h_datagen

  benchmark_prepare_drill

  BENCH_CURRENT_NUM_RUN="1" #reset the global counter

  # Iterate at least one time
  while true; do
    [ "$BENCH_NUM_RUNS" ] && logger "INFO: Starting iteration $BENCH_CURRENT_NUM_RUN of $BENCH_NUM_RUNS"

    for query in $BENCH_LIST ; do
      logger "INFO: RUNNING $query of $BENCH_NUM_RUNS runs"
      execute_query_drill "$query"
    done

    # Check if requested to iterate multiple times
    if [ ! "$BENCH_NUM_RUNS" ] || [[ "$BENCH_CURRENT_NUM_RUN" -ge "$BENCH_NUM_RUNS" ]] ; then
      break
    else
      BENCH_CURRENT_NUM_RUN="$((BENCH_CURRENT_NUM_RUN + 1))"
    fi
  done

  logger "INFO: DONE executing $BENCH_SUITE"
}




# $1 query number
execute_query_drill() {
  local query="$1"
  sed -i s/DATABASE/hive.$TPCH_DB_NAME/g $D2F_local_dir/tpch/queries/drill/$query.sql
  execute_drill "$query" "--force=true -f $D2F_local_dir/tpch/queries/drill/$query.sql" "time"
  sed -i s/hive.$TPCH_DB_NAME/DATABASE/g $D2F_local_dir/tpch/queries/drill/$query.sql
}

benchmark_prepare_drill(){

  # Copy hive-site.xml to hive conf folder (thrift server)
  cp $(get_base_configs_path)/hive1_conf_template/hive-site.xml $(get_local_apps_path)/apache-hive-1.2.1-bin/conf/
  logger "INFO: Starting metastore server"
  #execute_cmd_master "$bench_name" "$(get_hive_exports) $HIVE_HOME/bin/hive --service hiveserver2 &&"
  logger "INFO: Executing with hive"
  local hive_exports="$(get_hive_exports)"
  local hive_bin="$HIVE_HOME/bin/hive"
  local hive_cmd="$hive_exports
  $hive_bin --service metastore &"
  eval $hive_cmd
  logger "INFO: Wait 120 seconds to get server started..."
  sleep 120
  start_drill
  start_zookeeper
  logger "INFO: Wait 120 seconds to get zookeeper started..."
  sleep 120
  set_hive_plugin
}

benchmark_suite_cleanup() {
  clean_hadoop
  logger "INFO: Stopping HiveServer2"
  # kill hiveserver2 since there is no command to stop it...
  kill -9 $(ps aux | grep '[S]erver2' | awk '{print $2}')
  #stops metastore
  kill -9 $(lsof -t -i:9083)

}
